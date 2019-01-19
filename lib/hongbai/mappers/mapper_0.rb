module Hongbai
  module Nrom
    def mapper_init(prg_rom, chr_rom)
      @prg_data = Array.new(0x10000, 0)
      prg_addr_mask = prg_rom.length > 0x4000 ? 0x7fff : 0x3fff
      (0x8000..0xffff).each {|i| @prg_data[i] = prg_rom[i & prg_addr_mask] }

      # pre-compute the pattern table with all 8 possible attributes
      if chr_rom.size == 0
        @allow_write_to_rom = true
        @chr_rom = Array.new(0x2000, 0)
      else
        @allow_write_to_rom = false
        @chr_rom = chr_rom
      end
      @pattern_table = pre_compute_patterns(@chr_rom)

      # method catche
      @methods = {}
      [:read_ram0, :write_ram0, :read_ram1, :write_ram1, :prg_write,
       :nop_write, :chr_write,].each {|k| @methods[k] = method(k) } 
    end

    attr_reader :pattern_table

    # Read only
    def prg_write(addr, val)
      @prg_data[addr] = val if addr < 0x8000
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

    def chr_write(addr, val)
      # Chr rom is not modified in normal situations.
      # Once this method is called, we need to update the cached pattern table.
      @chr_rom[addr] = val
      pattern = addr / 2 + addr % 8
      @pattern_table[pattern] = build_pattern(pattern)
    end

    def nop_write(_addr, _val)
      STDERR.puts "Warn: Writing to CHR ROM"
    end

    def prg_read_method(_addr)
      @prg_data
    end

    def prg_write_method(_addr)
      @methods[:prg_write]
    end

    def chr_read_method(addr)
      case addr
      when (0..0x1fff) then @chr_rom
      when (0x2000..0x3fef)
        bank = @spec[:mirroring].mirror(addr)
        @methods[:"read_ram#{bank}"]
      end
    end

    def chr_write_method(addr)
      case addr
      when (0..0x1fff)
        @allow_write_to_rom ? @methods[:chr_store] : @methods[:nop_write]
      when (0x2000..0x3fef)
        bank = @spec[:mirroring].mirror(addr)
        @methods[:"write_ram#{bank}"]
      end
    end
  end

  Mapper = Nrom
end
