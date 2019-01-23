module Hongbai
  module MMC1
    def mapper_init(prg_rom, chr_rom)
      @prg_banks = prg_rom.each_slice(0x4000).to_a
      @chr_banks = chr_rom.each_slice(0x1000).to_a
      @prg_data = Array.new(0x10000, 0)
      @chr_data = Array.new(0x2000, 0)

      @prg_data[0x8000, 0x4000] = @prg_banks[0]
      @prg_data[0xc000, 0xffff] = @prg_banks[-1]

      # nametable
      vertical = [@ram0, @ram1, @ram0, @ram1]
      horizontal = [@ram0, @ram0, @ram1, @ram1]
      one_a = [@ram0] * 4
      one_b = [@ram1] * 4
      @nametables = [one_a, one_b, vertical, horizontal]
      @nt0, @nt1, @nt2, @nt3 = *@nametables[0]

      # registers
      @tmp = 0
      @count = 0
      @on_reg_update =
        [:set_control, :set_chr_bank_0, :set_chr_bank_1, :set_prg_bank].map {|m| method m }
      @prg_update_functions =
        [:prg_update_mode_0, :prg_update_mode_0, :prg_update_mode_2, :prg_update_mode_3].map {|m| method m }
      
      if @spec[:use_chr_ram]
        @on_reg_update[1] = @on_reg_update[2] = @methods[:nop_1]
        @chr_update_functions = [@methods[:nop]] * 2
      else
        @chr_update_functions =
          [:chr_update_mode_0, :chr_update_mode_1].map {|m| method m }
      end

      @prg_bank_mode = @chr_bank_mode = nil
      @chr_bank_0 = @chr_bank_1 = @prg_bank = 0
      @prg_ram_enabled = true
      @prg_update_function = @prg_update_functions[3]
      @chr_update_function = @chr_update_functions[0]
    end

    def prg_read_method(addr)
      case addr
      when PRG_RAM_RANGE then @methods[:read_prg_ram]
      else @prg_data
      end
    end

    def prg_write_method(addr)
      case addr
      when PRG_RAM_RANGE
        @spec[:has_prg_ram] ? @methods[:write_prg_ram] : @methods[:nop_2]
      when (0x8000..0xffff) then @methods[:write_8000]
      else @methods[:nop_2]
      end
    end

    def chr_read_method(addr)
      case addr
      when PATTERN_TABLE_RANGE then @chr_data
      when NAMETABLE_RANGE then @methods[:"read_nametable_#{addr / 0x400 % 4}"]
      end
    end

    def chr_write_method(addr)
      case addr
      when PATTERN_TABLE_RANGE
        @spec[:use_chr_ram] ? @chr_data.method(:[]=) : @methods[:nop_2]
      when NAMETABLE_RANGE then @methods[:"write_nametable_#{addr / 0x400 % 4}"]
      end
    end

    def write_8000(addr, val)
      if val[7] == 1
        @tmp = @count = 0
        set_prg_bank_mode 3
      else
        @tmp |= (val[0] << @count)
        @count += 1
        if @count == 5
          @on_reg_update[(addr >> 13) & 3][@tmp]
          @tmp = @count = 0
        end
      end
    end

    def set_control(val)
      @nt0, @nt1, @nt2, @nt3 = *@nametables[val & 3]
      set_prg_bank_mode((val >> 2) & 3)
      set_chr_bank_mode(val[4])
    end

    def set_prg_bank_mode(mode)
      return if mode == @prg_bank_mode
      @prg_bank_mode = mode
      @prg_update_function = @prg_update_functions[@prg_bank_mode]
      @prg_update_function.call
    end

    def set_chr_bank_mode(mode)
      return if mode == @chr_bank_mode
      @chr_bank_mode = mode
      @chr_update_function = @chr_update_functions[@chr_bank_mode]
      @chr_update_function.call
    end

    def set_chr_bank_0(val)
      @chr_bank_0 = val
      @chr_update_function.call
    end

    def set_chr_bank_1(val)
      @chr_bank_1 = val
      @chr_update_function.call if @chr_bank_mode == 1
    end

    def set_prg_bank(val)
      @prg_ram_enabled = val[4] == 0
      @prg_bank = val & 0xf
      @prg_update_function.call
    end

    def prg_update_mode_0
      bank = @prg_bank & 0xe
      @prg_data[0x8000, 0x4000] = @prg_banks[bank]
      @prg_data[0xc000, 0x4000] = @prg_banks[bank + 1]
    end

    def prg_update_mode_2
      @prg_data[0x8000, 0x4000] = @prg_banks[0]
      @prg_data[0xc000, 0x4000] = @prg_banks[@prg_bank]
    end

    def prg_update_mode_3
      @prg_data[0x8000, 0x4000] = @prg_banks[@prg_bank]
      @prg_data[0xc000, 0x4000] = @prg_banks[-1]
    end

    def chr_update_mode_0
      bank = @chr_bank_0 & 0xe
      @chr_data[0, 0x1000] = @chr_banks[bank]
      @chr_data[0x1000, 0x1000] = @chr_banks[bank + 1]
    end

    def chr_update_mode_1
      @chr_data[0, 0x1000] = @chr_banks[@chr_bank_0]
      @chr_data[0x1000, 0x1000] = @chr_banks[@chr_bank_1]
    end

    def read_prg_ram(addr)
      @prg_ram_enabled ? @prg_data[addr] : (addr >> 8)
    end

    def write_prg_ram(addr, val)
      @prg_data[addr] = val if @prg_ram_enabled
    end

    def_read = "def read_nametable_%d(addr); @nt%d[addr & 0x3ff] end"
    def_write = "def write_nametable_%d(addr, val); @nt%d[addr & 0x3ff] = val end"
    (0..3).each do |i|
      eval def_read % [i, i]
      eval def_write % [i, i]
    end
  end

  Mapper = MMC1
end
