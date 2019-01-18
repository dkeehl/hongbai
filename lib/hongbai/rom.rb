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
          new(prg_rom, chr_rom, trainer, mapper, mirroring, tv)
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
    private_class_method :new

    private
      def initialize(prg_rom, chr_rom, trainer, mapper, mirroring, tv_system)
        @prg_rom = prg_rom
        @chr_rom = chr_rom
        @trainer = trainer
        @mapper = mapper
        @mirroring = mirroring
        @tv_system = tv_system

        @allow_write_to_rom = false
        make_mapper
      end


      def make_mapper
        # Only support mapper0 at the moment
        require_relative "./mappers/mapper_#{@mapper}"
        singleton_class.class_eval { include Mapper }
        mapper_init
      end
  end

  class Mirroring
    def initialize
      @ram = Array.new(0x800, 0xff)
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

      def read_ram_0(addr)
        @ram[addr & 0x3ff]
      end

      def write_ram_0(addr, val)
        @ram[addr & 0x3ff] = val
      end

      def read_ram_2(addr)
        @ram[(addr & 0x3ff) + 0x400]
      end

      def write_ram_2(addr, val)
        @ram[(addr & 0x3ff) + 0x400] = val
      end

      def ram_read_method(addr)
        (addr / 0x800).even? ?  method(:read_ram_0) : method(:read_ram_2)
      end

      def ram_write_method(addr)
        (addr / 0x800).even? ? method(:write_ram_0) : method(:write_ram_2)
      end
    end

    class FourScreens < self
      def to_s; "4-Screen" end
    end
  end
end
