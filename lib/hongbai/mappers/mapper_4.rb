module Hongbai
  module MMC3
    # This may look a little confusing. For the ppu addresses and the cpu
    # addresses to be updated are never coincide with each other, we just mix
    # them together.
    UPDATE_ADDRS = [
      [0x0000, 0x0800, 0x1000, 0x1400, 0x1800, 0x1c00, 0x8000, 0xa000], # mode 0 no swap
      [0x0000, 0x0800, 0x1000, 0x1400, 0x1800, 0x1c00, 0xc000, 0xa000], # mode 1 prg swap
      [0x1000, 0x1800, 0x0000, 0x0400, 0x0800, 0x0c00, 0x8000, 0xa000], # mode 2 chr swap
      [0x1000, 0x1800, 0x0000, 0x0400, 0x0800, 0x0c00, 0xc000, 0xa000], # mode 4 both swap
    ]

    RANGE_8 = (0x8000..0x9fff)
    RANGE_A = (0xa000..0xbfff)
    RANGE_C = (0xc000..0xdfff)
    RANGE_E = (0xe000..0xffff)

    def mapper_init(prg_rom, chr_rom)
      @prg_banks = prg_rom.each_slice(0x2000).to_a
      @chr_banks = chr_rom.each_slice(0x400).to_a
      @prg_data = Array.new(0x10000, 0)
      @chr_data = Array.new(0x2000, 0)

      @pattern_banks = @chr_banks.map {|bank| pre_compute_patterns bank }
      @pattern_table = Array.new(0x1000, Array.new(8, [0] * 8))

      # initialize prg address $c000-$ffff
      @prg_data[0xc000, 0x2000] = @prg_banks[-2]
      @prg_data[0xe000, 0x2000] = @prg_banks[-1] 

      # name table
      @nametable = @vertical = [@ram0, @ram1, @ram0, @ram1]
      @horizontal = [@ram0, @ram0, @ram1, @ram1]

      # data mapping
      @update_functions =
        ([:update_chr_2] * 2 + [:update_chr_1] * 4 + [:update_prg] * 2).map {|m| method m }
      @swap_functions = [:nop, :swap_prg, :swap_chr, :swap_prg_and_chr].map {|m| method m }
      @swap_mode = 0
      @update_function = @update_functions[0]
      @update_addr = UPDATE_ADDRS[@swap_mode][0]

      # prg ram
      @prg_ram_enabled = false
      @prg_ram_writable = false

      # irq
      @irq_enabled = false
      @irq_latch = 0
      @count = 0
      @irq_function = [@methods[:set_clock], @methods[:nop]]
    end

    def pattern_table
      @methods[:read_pattern_table]
    end

    def prg_read_method(addr)
      case addr
      when PRG_RAM_RANGE then @methods[:read_prg_ram]
      else @prg_data
      end
    end

    def prg_write_method(addr)
      case addr
      when PRG_RAM_RANGE then @methods[:write_prg_ram]
      when RANGE_8 
        addr.even? ? @methods[:write_8000] : @methods[:write_8001]
      when RANGE_A
        addr.even? ? @methods[:write_a000] : @methods[:write_a001]
      when RANGE_C
        addr.even? ? @methods[:write_c000] : @methods[:write_c001]
      when RANGE_E
        addr.even? ? @methods[:write_e000] : @methods[:write_e001]
      else @methods[:nop_2]
      end
    end

    def chr_read_method(addr)
      case addr
      when PATTERN_TABLE_RANGE then @chr_data
      when NAMETABLE_RANGE then @methods[:read_nametable]
      end
    end

    def chr_write_method(addr)
      case addr
      when PATTERN_TABLE_RANGE then @methods[:nop_2]
      when NAMETABLE_RANGE then @methods[:write_nametable]
      end
    end

    def write_8000(_addr, val)
      select = val & 7
      @update_function = @update_functions[select]
      swap_mode = val >> 6
      @update_addr = UPDATE_ADDRS[swap_mode][select]
      @swap_functions[swap_mode ^ @swap_mode].call
      @swap_mode = swap_mode
    end

    def write_8001(_addr, val)
      @update_function[val]
    end

    def write_a000(_addr, val)
      @nametable = val[0] == 0 ? @vertical : @horizontal
    end

    def write_a001(_addr, val)
      @prg_ram_enabled = val[7] == 1
      @prg_ram_writable = @prg_ram_enabled && val[6] == 0
    end

    def write_c000(_addr, val)
      @irq_latch = val
    end

    def write_c001(_addr, _val)
      @count = 0
    end

    def write_e000(_addr, _val)
      @irq_enabled = false
      @console.rom_irq = false
    end

    def write_e001(_addr, _val)
      @irq_enabled = true
    end

    # select 8K prg bank
    def update_prg(bank)
      @prg_data[@update_addr, 0x2000] = @prg_banks[bank % @prg_banks.size]
    end

    # select 1k chr bank
    def update_chr_1(bank)
      bank %= @chr_banks.size
      @chr_data[@update_addr, 0x400] = @chr_banks[bank]
      @pattern_table[@update_addr >> 1, 0x200] = @pattern_banks[bank]
    end

    # select 2k chr bank
    def update_chr_2(bank)
      bank = (bank & 0xfe) % @chr_banks.size
      pattern_addr = @update_addr >> 1
      @chr_data[@update_addr, 0x400] = @chr_banks[bank]
      @pattern_table[pattern_addr, 0x200] = @pattern_banks[bank]
      @chr_data[@update_addr + 0x400, 0x400] = @chr_banks[bank + 1]
      @pattern_table[pattern_addr + 0x200, 0x200] = @pattern_banks[bank + 1]
    end

    def swap_prg
      @prg_data[0x8000, 0x2000], @prg_data[0xc000, 0x2000] =
        @prg_data[0xc000, 0x2000], @prg_data[0x8000, 0x2000]
    end

    def swap_chr
      @chr_data.rotate! 0x1000
      @pattern_table.rotate! 0x800
    end

    def swap_prg_and_chr
      @prg_data[0x8000, 0x2000], @prg_data[0xc000, 0x2000] =
        @prg_data[0xc000, 0x2000], @prg_data[0x8000, 0x2000]
      @chr_data.rotate! 0x1000
      @pattern_table.rotate! 0x800
    end

    # IRQ clock is not accurate. Only applies to the most normal case.
    def read_pattern_table(tile_num)
      @irq_function[tile_num[11]].call
      @pattern_table[tile_num]
    end

    def set_clock
      @irq_function[0] = @methods[:nop]
      @irq_function[1] = @methods[:clock_counter]
    end

    def clock_counter
      @irq_function[0] = @methods[:set_clock]
      @irq_function[1] = @methods[:nop]
      if @count == 0
        @count = @irq_latch
      else
        @count -= 1
      end
      @console.rom_irq = true if @irq_enabled && @count == 0
    end

    def read_nametable(addr)
      @nametable[(addr >> 10) & 3][addr & 0x3ff]
    end

    def write_nametable(addr, val)
      @nametable[(addr >> 10) & 3][addr & 0x3ff] = val
    end

    def read_prg_ram(addr)
      @prg_ram_enabled ? @prg_data[addr] : (addr >> 8)
    end

    def write_prg_ram(addr, val)
      @prg_data[addr] = val if @prg_ram_writable
    end
  end

  Mapper = MMC3
end
