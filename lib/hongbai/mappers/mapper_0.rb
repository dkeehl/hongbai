module Hongbai
  module Nrom
    def mapper_init(prg_rom, chr_rom)
      @prg_data = Array.new(0x10000, 0)
      prg_addr_mask = prg_rom.length > 0x4000 ? 0x7fff : 0x3fff
      (0x8000..0xffff).each {|i| @prg_data[i] = prg_rom[i & prg_addr_mask] }

      if chr_rom.size == 0
        @use_prg_ram = true
        @chr_rom = Array.new(0x2000, 0)
      else
        @use_prg_ram = false
        @chr_rom = chr_rom
      end
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

    def prg_read_method(_addr)
      @prg_data
    end

    def prg_write_method(_addr)
      @prg_data.method(:[]=)
    end

    def chr_read_method(addr)
      case addr
      when PATTERN_TABLE_RANGE then @chr_rom
      when NAMETABLE_RANGE 
        bank = @spec[:mirroring].mirror(addr)
        @methods[:"read_ram#{bank}"]
      end
    end

    def chr_write_method(addr)
      case addr
      when PATTERN_TABLE_RANGE
        @use_prg_ram ? @chr_rom.method(:[]=) : @methods[:nop_2]
      when NAMETABLE_RANGE
        bank = @spec[:mirroring].mirror(addr)
        @methods[:"write_ram#{bank}"]
      end
    end
  end

  Mapper = Nrom
end
