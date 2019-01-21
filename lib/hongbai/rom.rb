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

    def initialize(spec, buf)
      @spec = spec
      @buf = buf
    end

    def inspect
      "NES ROM\n"\
      "PRG ROM size: #{@spec[:prg_rom_size] / 1024} KB\n"\
      "CHR ROM size: #{@spec[:chr_rom_size] / 1024} KB\n"\
      "Mapper Number: #{@spec[:mapper]}\n"\
      "Mirroring Mode: #{@spec[:mirroring]}\n"\
      "TV System: #{@spec[:tv_system]}\n"
    end

    def insert_to(console)
      @console = console
      @methods = Hash.new {|hash, key| hash[key] = method(key) }
      @ram0 = Array.new(0x400, 0)
      @ram1 = Array.new(0x400, 0)

      @trainer = @buf.slice!(0, 512) if @spec[:has_trainer]
      prg_rom = @buf.slice!(0, @spec[:prg_rom_size])
      chr_rom = @buf.slice!(0, @spec[:chr_rom_size])

      require_relative "./mappers/mapper_#{@spec[:mapper]}"
      singleton_class.class_eval { include Mapper }
      mapper_init(prg_rom, chr_rom)
    end

    def pre_compute_patterns(array)
      array.each_slice(16).map do |a|
        plane0 = a[0, 8]
        plane1 = a[8, 8]
        (0..7).map do |y|
          lo = plane0[y]
          hi = plane1[y]
          (0..7).map do |attribute|
            attribute <<= 2
            (0..7).map do |x|
              color = (hi[7 - x] << 1) | lo[7 - x]
              color == 0 ? 0 : attribute | color
            end
          end
        end
      end.flatten!(1)
    end

    private_class_method :new
  end

  class Mirroring
    class Vertical < self
      def self.to_s; "Vertical" end

      # returns 0 if an adderss is mapped to RAM $000-$3ff;
      # returns 1 if an address is mapped to RAM $400-$7ff
      def self.mirror(addr)
        addr / 0x400 % 2
      end
    end

    class Horizontal < self
      def self.to_s; "Horizontal" end

      def self.mirror(addr)
        addr / 0x800 % 2
      end
    end

    class FourScreens < self
      def self.to_s; "4-Screen" end
    end
  end
end
