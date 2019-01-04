module Hongbai
  class INes
    class << self
      # String -> INes
      def from_file(file)
        File.open(file, 'r') do |f|
          header = f.read(16)
          if header[0..3] != "NES\x1A"
            puts "Invalid file format"
            return nil
          end
          bytes = header.unpack("C*")
          prg_rom_size = bytes[4]
          chr_rom_size = bytes[5]
          flag6 = bytes[6]
          flag7 = bytes[7]
          _prg_ram_size = bytes[8]
          flag9 = bytes[9]
          mapper = mapper_number(flag6, flag7)
          mirroring = mirroring_mode(flag6)
          tv = tv_system(flag9)
          if has_trainer? flag6
            trainer = f.read(512).unpack("C*")
          end
          prg_rom = f.read(prg_rom_size * 16384).unpack("C*")
          chr_rom = f.read(chr_rom_size * 8192).unpack("C*")
          INes.new(prg_rom, chr_rom, trainer, mapper, mirroring, tv)
        end
      end

      def has_trainer?(flag6)
        (flag6 >> 3) & 1 == 1
      end

      def mapper_number(flag6, flag7)
        (flag7 & 0xf0) | (flag6 >> 4)
      end

      def mirroring_mode(flag6)
        if (flag6 >> 3) & 1 == 1
          Mirroring::FourScreens.new
        elsif flag6 & 1 == 1
          Mirroring::Vertical.new
        else
          Mirroring::Horizontal.new
        end
      end

      def tv_system(flag9)
        flag9 & 1 == 0 ? "NTSC" : "PAL"
      end
    end

    # INes -> String
    def inspect
      "NES ROM\n"\
      "PRG ROM size: #{@prg_rom.length / 1024} KB\n"\
      "CHR ROM size: #{@chr_rom.length / 1024} KB\n"\
      "Mapper Number: #{@mapper}\n"\
      "Mirroring Mode: #{@mirroring}\n"\
      "TV System: #{@tv_system}\n"
    end

    attr_reader :mirroring

    private
      def self.new(prg_rom, chr_rom, trainer, mapper, mirroring, tv_system)
        super
      end

      def initialize(prg_rom, chr_rom, trainer, mapper, mirroring, tv_system)
        @prg_rom = prg_rom
        @chr_rom = chr_rom
        @trainer = trainer
        @mapper = mapper
        @mirroring = mirroring
        @tv_system = tv_system

        make_mapper
      end


      def make_mapper
        # Only support mapper0 at the moment
        mapper = case @mapper
                 when 0 then Nrom
                 else
                   raise "Unsupported mapper"
                 end
        singleton_class.class_eval { include mapper }
        mapper_init
      end
  end

  class Mirroring
    def initialize
      @ram = Array.new(0x800, 0)
    end

    class Vertical < self
      def to_s; "Vertical" end

      def read_ram(addr)
        @ram[addr & 0x7ff]
      end

      def write_ram(addr, val)
        @ram[addr & 0x7ff] = val
      end

      def ram_read_method(_addr)
        method :read_ram
      end

      def ram_write_method(_addr)
        method :write_ram
      end
    end

    class Horizontal < self
      def to_s; "Horizontal" end

      def read_ram_1(addr)
        @ram[addr & 0x3ff]
      end

      def write_ram_1(addr, val)
        @ram[addr & 0x3ff] = val
      end

      def read_ram_3(addr)
        @ram[(addr & 0x3ff) + 0x400]
      end

      def write_ram_3(addr, val)
        @ram[(addr & 0x3ff) + 0x400] = val
      end

      def ram_read_method(addr)
        (addr / 0x800).even? ?  method(:read_ram_1) : method(:read_ram_3)
      end

      def ram_write_method(addr)
        (addr / 0x800).even? ? method(:write_ram_1) : method(:write_ram_3)
      end
    end

    class FourScreens < self
      def to_s; "4-Screen" end
    end
  end

  # Mapper 0
  module Nrom
    def mapper_init
      @prg_data = Array.new(0x10000, 0)
      prg_addr_mask = @prg_rom.length > 16384 ? 0x7fff : 0x3fff
      (0x8000..0xffff).each {|i| @prg_data[i] = @prg_rom[i & prg_addr_mask] }
    end

    def next_scanline_irq; false end

    # Read only
    def prg_write(addr, val)
      @prg_data[addr] = val if addr < 0x8000
    end

    # Read only
    def chr_store(_addr, _val); end

    def prg_read_method
      @prg_data
    end

    def prg_write_method
      method :prg_write
    end

    def chr_read_method
      @chr_rom
    end

    def chr_write_method
      method :chr_store
    end
  end
end
