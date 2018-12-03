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
          Mirroring::FourScreens
        elsif flag6 & 1 == 1
          Mirroring::Vertical
        else
          Mirroring::Horizontal
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
      end
  end

  class Mirroring
    class Vertical < self
      def self.to_s; "Vertical" end
    end

    class Horizontal < self
      def self.to_s; "Horizontal" end
    end

    class FourScreens < self
      def self.to_s; "FourScreens" end
    end
  end
end
