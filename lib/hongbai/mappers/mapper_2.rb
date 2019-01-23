module Hongbai
  module UxROM
    def mapper_init(prg_rom, chr_rom)
      @prg_banks = prg_rom.each_slice(0x4000).to_a

      @prg_data = Array.new(0x10000, 0)
      (0x4020..0x7fff).each {|i| @prg_data[i] = i >> 8 }
      @prg_data[0xc000, 0x4000] = @prg_banks[-1]

      @chr_data = @spec[:use_chr_ram] ? Array.new(0x2000, 0) : chr_rom
    end

    def read_ram0(addr)
      @ram0[addr & 0x3ff]
    end

    def read_ram1(addr)
      @ram1[addr & 0x3ff]
    end

    def write_ram0(addr, val)
      @ram0[addr & 0x3ff] = val
    end

    def write_ram1(addr, val)
      @ram1[addr & 0x3ff] = val
    end

    def write_8000(_addr, val)
      bank = val % @prg_banks.size
      if bank != @bank
        @bank = bank
        @prg_data[0x8000, 0x4000] = @prg_banks[@bank]
      end
    end

    def prg_read_method(_addr)
      @prg_data
    end

    def prg_write_method(addr)
      addr > 0x7fff ? @methods[:write_8000] : @methods[:nop_2]
    end

    def chr_read_method(addr)
      case addr
      when PATTERN_TABLE_RANGE then @chr_data
      when NAMETABLE_RANGE 
        bank = @spec[:mirroring].mirror(addr)
        @methods[:"read_ram#{bank}"]
      end
    end

    def chr_write_method(addr)
      case addr
      when PATTERN_TABLE_RANGE
        @spec[:use_chr_ram] ? @chr_data.method(:[]=) : @methods[:nop_2]
      when NAMETABLE_RANGE
        bank = @spec[:mirroring].mirror(addr)
        @methods[:"write_ram#{bank}"]
      end
    end
  end

  Mapper = UxROM
end
