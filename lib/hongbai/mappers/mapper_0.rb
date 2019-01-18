module Hongbai
  # Mapper 0
  module Nrom
    def mapper_init
      @prg_data = Array.new(0x10000, 0)
      prg_addr_mask = @prg_rom.length > 16384 ? 0x7fff : 0x3fff
      (0x8000..0xffff).each {|i| @prg_data[i] = @prg_rom[i & prg_addr_mask] }

      # pre-compute the pattern table with all 8 possible attributes
      if @chr_rom.size == 0
        @allow_write_to_rom = true
        @chr_rom = Array.new(0x2000, 0)
      end
      @pattern_table = (0..0xfff).map {|pattern| build_pattern pattern }
    end

    attr_reader :pattern_table

    # pattern in (0..0xfff) -> Array<8, 8>
    def build_pattern(pattern)
      tile_num, fine_y  = pattern.divmod(8)
      panel_0_addr = tile_num * 16 + fine_y
      (0..7).map do |attribute|
        attribute <<= 2
        (0..7).map do |x|
          bitmap_low = @chr_rom[panel_0_addr]
          bitmap_high = @chr_rom[panel_0_addr + 8]
          color = (bitmap_high[7 - x] << 1) | bitmap_low[7 - x]
          color == 0 ? 0 : attribute | color
        end
      end
    end

    # Read only
    def prg_write(addr, val)
      @prg_data[addr] = val if addr < 0x8000
    end

    def chr_store(addr, val)
      # Chr rom is not modified in normal situations.
      # Once this method is called, we need to update the cached pattern table.
      @chr_rom[addr] = val
      pattern = addr / 2 + addr % 8
      @pattern_table[pattern] = build_pattern(pattern)
    end

    def prg_read_method
      @prg_data
    end

    def nop_write(_addr, _val)
      STDERR.puts "Warn: Writing to CHR ROM"
    end

    def prg_write_method
      method :prg_write
    end

    def chr_read_method
      @chr_rom
    end

    def chr_write_method
      @allow_write_to_rom ? method(:chr_store) : method(:nop_write)
    end
  end

  Mapper = Nrom
end
