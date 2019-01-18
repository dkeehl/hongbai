module Hongbai
  class Rom
    class << self
      def from_file(file)
        buf = File.binread(file)
        header = buf.slice!(0, 16)
        spec = parse_header(header)
        if size_checks?(spec, buf)
          return new(spec, buf.bytes)  
        else
          raise "bad file size"
        end
      end

      def parse_header(header)
        raise "Invalid file format" if header[0..3] != "NES\x1A"
        header = header.bytes
        spec = {}
        prg_rom_size, chr_rom_size, flag6, flag7, _prg_ram_size, flag9 = header[4..9]
        spec[:prg_rom_size] = prg_rom_size * 0x4000
        spec[:chr_rom_size] = chr_rom_size * 0x2000
        spec[:has_prg_ram] = flag6[1] == 1
        spec[:has_trainer] = flag6[2] == 1
        spec[:mapper] = (flag7 & 0xf0) | (flag6 >> 4)
        spec[:mirroring] = mirroring_mode(flag6)
        spec[:tv_system] = flag9[0] == 0 ? :NTSC : :PAL
        spec
      end

      def mirroring_mode(flag6)
        if flag6[3] == 1
          Mirroring::FourScreens
        elsif flag6[0] == 1
          Mirroring::Vertical
        else
          Mirroring::Horizontal
        end
      end

      def size_checks?(spec, buf)
        expect_size = spec[:prg_rom_size] + spec[:chr_rom_size]
        expect_size += 512 if spec[:has_trainer]
        buf.size == expect_size
      end
    end

    def inspect
      "NES ROM\n"\
      "PRG ROM size: #{@spec[:prg_rom_size] / 1024} KB\n"\
      "CHR ROM size: #{@spec[:chr_rom_size] / 1024} KB\n"\
      "Mapper Number: #{@spec[:mapper]}\n"\
      "Mirroring Mode: #{@mirroring}\n"\
      "TV System: #{@spec[:tv_system]}\n"
    end

    attr_reader :mirroring
    private_class_method :new

    def initialize(spec, buf)
      @spec = spec
      @trainer = buf.slice!(0, 512) if @spec[:has_trainer]
      @mirroring = @spec[:mirroring].new
      prg_rom = buf.slice!(0, @spec[:prg_rom_size])
      chr_rom = buf.slice!(0, @spec[:chr_rom_size])

      require_relative "./mappers/mapper_#{@spec[:mapper]}"
      singleton_class.class_eval { include Mapper }
      mapper_init(prg_rom, chr_rom)
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
