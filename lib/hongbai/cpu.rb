module Hongbai
  class Register
    def initialize
      @value = 0
    end

    def add(n)
      @value += n
      mask_off
    end

    def value
      @value
    end

    def mask_off
      @value &= 0xff
    end

    def load(n)
      @value = n
    end
  end

  class ProgramCounter < Register
    def mask_off
      @value &= 0xffff
    end

    def step(n = 1)
      @value += n
    end

    def relative_move(n)
      if n > 127
        @value = @value - 256 + n
      else
        @value += n
      end
    end
  end

  class StatusRegister
    def initialize
      @carry = false
      @zero = false
      @disable_interrupt = false
      @decimal_mode = false
      @break = false
      @bit5 = 0b0010_0000
      @overflow = false
      @negative = false
    end

    attr_writer :carry, :zero, :overflow, :negative

    def value
      bit0 = @carry ? 0b0000_0001 : 0
      bit1 = @zero  ? 0b0000_0010 : 0
      bit2 = @disable_interrupt ? 0b0000_0100 : 0
      bit3 = @decimal_mode ? 0b0000_1000 : 0
      bit4 = @break ? 0b0001_0000 : 0
      bit6 = @overflow ? 0b0100_0000 : 0
      bit7 = @negative ? 0b1000_0000 : 0
      bit0 + bit1 + bit2 + bit3 + bit4 + @bit5 + bit6 + bit7
    end

    def load(n)
      @carry = n[0] == 1
      @zero = n[1] == 1
      @disable_interrupt = n[2] == 1
      @decimal_mode = n[3] == 1
      @break = n[4] == 1
      @overflow = n[6] == 1
      @negative = n[7] == 1
    end

    def carry_flag?
      @carry
    end

    def set_carry_flag
      @carry = true
    end

    def clear_carry_flag
      @carry = false
    end

    def zero_flag?
      @zero
    end

    def set_zero_flag
      @zero = true
    end

    def clear_zero_flag
      @zero = false
    end

    def interrupt_disabled?
      @disable_interrupt
    end

    def disable_interrupt
      @disable_interrupt = true
    end
    
    def enable_interrupt
      @disable_interrupt = false
    end

    def decimal_mode?
      @decimal_mode
    end

    def set_decimal_mode
      @decimal_mode = true
    end

    def unset_decimal_mode
      @decimal_mode = false
    end

    def break_commond?
      @break
    end

    def set_break_commond
      @break = true
    end

    def unset_break_commond
      @break = false
    end

    def overflow_flag?
      @overflow
    end

    def set_overflow_flag
      @overflow = true
    end

    def clear_overflow_flag
      @overflow = false
    end

    def negative_flag?
      @negative
    end

    def set_negative_flag
      @negative = true
    end

    def clear_negative_flag
      @negative = false
    end
  end

  class Cpu
    NMI_VECTOR = 0xfffa
    BRK_VECTOR = 0xfffe
    RESET_VECTOR = 0xfffc

    def initialize(mem)
      @m = mem
      @a = Register.new             #Accumulator Register
      @x = Register.new             #Index Register X
      @y = Register.new             #Index Register Y
      @pc = ProgramCounter.new
      @sp = Register.new            #Stack Pointer
      @p = StatusRegister.new
      @counter = 0

      @p.load(0x34)
      @sp.load(0xfd)
      @pc.load(read_u16(RESET_VECTOR))

      @trace = false
    end

    attr_accessor :trace

    def step
      opcode = @m.fetch(@pc.value)
      run(opcode)
    end

    def suspend(cycles)
      @counter += cycles
    end

    def nmi
      push(@pc.value >> 8)
      push(@pc.value & 0xff)
      push(@p.value)
      @p.disable_interrupt
      @pc.load(read_u16(NMI_VECTOR))
    end

    def irq
      return if interrupt_disabled?

      push(@pc.value >> 8)
      push(@pc.value & 0xff)
      push(@p.value)
      @p.disable_interrupt
      @pc.load(read_u16(BRK_VECTOR))
    end

    def read_u16(addr)
      lo = @m.read(addr)
      hi = @m.read(addr + 1)
      (hi << 8) | lo
    end
    #############################
    #States accessors
    #############################
    #def accumulator
    #  @a.value
    #end

    #def x_register
    #  @x.value
    #end

    #def y_register
    #  @y.value
    #end

    #def pc
    #  @pc.value
    #end

    #def p_register
    #  @p.value
    #end

    #def stack_pointer
    #  @sp.value
    #end

    #def mem
    #  @m
    #end

    def cycle
      @counter
    end

    #########################
    #OPCODES
    #########################
    OP_TABLE = {
      # code => [instruction, addressing, bytes, cycles]
      0x69 => [:adc, :immediate,   2, 2],
      0x65 => [:adc, :zero_page,   2, 3],
      0x75 => [:adc, :zero_page_x, 2, 4],
      0x6d => [:adc, :absolute,    3, 4],
      0x7d => [:adc, :absolute_x,  3, 4],
      0x79 => [:adc, :absolute_y,  3, 4],
      0x61 => [:adc, :indirect_x,  2, 6],
      0x71 => [:adc, :indirect_y,  2, 5],

      0x29 => [:und, :immediate,   2, 2],
      0x25 => [:und, :zero_page,   2, 3],
      0x35 => [:und, :zero_page_x, 2, 4],
      0x2d => [:und, :absolute,    3, 4],
      0x3d => [:und, :absolute_x,  3, 4],
      0x39 => [:und, :absolute_y,  3, 4],
      0x21 => [:und, :indirect_x,  2, 6],
      0x31 => [:und, :indirect_y,  2, 5],

      0x0a => [:asl, :accumulator, 1, 2],
      0x06 => [:asl, :zero_page,   2, 5],
      0x16 => [:asl, :zero_page_x, 2, 6],
      0x0e => [:asl, :absolute,    3, 6],
      0x1e => [:asl, :absolute_x,  3, 7],

      0x90 => [:bcc, :relative,    2, 2],
      0xb0 => [:bcs, :relative,    2, 2],
      0xf0 => [:beq, :relative,    2, 2],

      0x24 => [:bit, :zero_page,   2, 3],
      0x2c => [:bit, :absolute,    3, 4],

      0x30 => [:bmi, :relative,    2, 2],
      0xd0 => [:bne, :relative,    2, 2],
      0x10 => [:bpl, :relative,    2, 2],
      0x00 => [:brk, :implied,     1, 7],
      0x50 => [:bvc, :relative,    2, 2],
      0x70 => [:bvs, :relative,    2, 2],
      0x18 => [:clc, :implied,     1, 2],
      0xd8 => [:cld, :implied,     1, 2],
      0x58 => [:cli, :implied,     1, 2],
      0xb8 => [:clv, :implied,     1, 2],

      0xc9 => [:cmp, :immediate,   2, 2],
      0xc5 => [:cmp, :zero_page,   2, 3],
      0xd5 => [:cmp, :zero_page_x, 2, 4],
      0xcd => [:cmp, :absolute,    3, 4],
      0xdd => [:cmp, :absolute_x,  3, 4],
      0xd9 => [:cmp, :absolute_y,  3, 4],
      0xc1 => [:cmp, :indirect_x,  2, 6],
      0xd1 => [:cmp, :indirect_y,  2, 5],

      0xe0 => [:cpx, :immediate,   2, 2],
      0xe4 => [:cpx, :zero_page,   2, 3],
      0xec => [:cpx, :absolute,    3, 4],

      0xc0 => [:cpy, :immediate,   2, 2],
      0xc4 => [:cpy, :zero_page,   2, 3],
      0xcc => [:cpy, :absolute,    3, 4],

      0xc6 => [:dec, :zero_page,   2, 5],
      0xd6 => [:dec, :zero_page_x, 2, 6],
      0xce => [:dec, :absolute,    3, 6],
      0xde => [:dec, :absolute_x,  3, 7],

      0xca => [:dex, :implied,     1, 2],
      0x88 => [:dey, :implied,     1, 2],

      0x49 => [:eor, :immediate,   2, 2],
      0x45 => [:eor, :zero_page,   2, 3],
      0x55 => [:eor, :zero_page_x, 2, 4],
      0x4d => [:eor, :absolute,    3, 4],
      0x5d => [:eor, :absolute_x,  3, 4],
      0x59 => [:eor, :absolute_y,  3, 4],
      0x41 => [:eor, :indirect_x,  2, 6],
      0x51 => [:eor, :indirect_y,  2, 5],

      0xe6 => [:inc, :zero_page,   2, 5],
      0xf6 => [:inc, :zero_page_x, 2, 6],
      0xee => [:inc, :absolute,    3, 6],
      0xfe => [:inc, :absolute_x,  3, 7],

      0xe8 => [:inx, :implied,     1, 2],
      0xc8 => [:iny, :implied,     1, 2],

      0x4c => [:jmp, :absolute,    3, 3],
      0x6c => [:jmp, :indirect,    3, 5],

      0x20 => [:jsr, :absolute,    3, 6],

      0xa9 => [:lda, :immediate,   2, 2],
      0xa5 => [:lda, :zero_page,   2, 3],
      0xb5 => [:lda, :zero_page_x, 2, 4],
      0xad => [:lda, :absolute,    3, 4],
      0xbd => [:lda, :absolute_x,  3, 4],
      0xb9 => [:lda, :absolute_y,  3, 4],
      0xa1 => [:lda, :indirect_x,  2, 6],
      0xb1 => [:lda, :indirect_y,  2, 5],

      0xa2 => [:ldx, :immediate,   2, 2],
      0xa6 => [:ldx, :zero_page,   2, 3],
      0xb6 => [:ldx, :zero_page_y, 2, 4],
      0xae => [:ldx, :absolute,    3, 4],
      0xbe => [:ldx, :absolute_y,  3, 4],

      0xa0 => [:ldy, :immediate,   2, 2],
      0xa4 => [:ldy, :zero_page,   2, 3],
      0xb4 => [:ldy, :zero_page_x, 2, 4],
      0xac => [:ldy, :absolute,    3, 4],
      0xbc => [:ldy, :absolute_x,  3, 4],

      0x4a => [:lsr, :accumulator, 1, 2],
      0x46 => [:lsr, :zero_page,   2, 5],
      0x56 => [:lsr, :zero_page_x, 2, 4],
      0x4e => [:lsr, :absolute,    3, 4],
      0x5e => [:lsr, :absolute_x,  3, 7],

      0xea => [:nop, :implied,     1, 2],

      0x09 => [:ora, :immediate,   2, 2],
      0x05 => [:ora, :zero_page,   2, 3],
      0x15 => [:ora, :zero_page_x, 2, 4],
      0x0d => [:ora, :absolute,    3, 4],
      0x1d => [:ora, :absolute_x,  3, 4],
      0x19 => [:ora, :absolute_y,  3, 4],
      0x01 => [:ora, :indirect_x,  2, 6],
      0x11 => [:ora, :indirect_y,  2, 5],

      0x48 => [:pha, :implied,     1, 3],
      0x08 => [:php, :implied,     1, 3],
      0x68 => [:pla, :implied,     1, 4],
      0x28 => [:plp, :implied,     1, 4],

      0x2a => [:rol, :accumulator, 1, 2],
      0x26 => [:rol, :zero_page,   2, 5],
      0x36 => [:rol, :zero_page_x, 2, 6],
      0x2e => [:rol, :absolute,    3, 6],
      0x3e => [:rol, :absolute_x,  3, 7],

      0x6a => [:ror, :accumulator, 1, 2],
      0x66 => [:ror, :zero_page,   2, 5],
      0x76 => [:ror, :zero_page_x, 2, 6],
      0x6e => [:ror, :absolute,    3, 6],
      0x7e => [:ror, :absolute_x,  3, 7],

      0x40 => [:rti, :implied,     1, 6],
      0x60 => [:rts, :implied,     1, 6],

      0xe9 => [:sbc, :immediate,   2, 2],
      0xe5 => [:sbc, :zero_page,   2, 3],
      0xf5 => [:sbc, :zero_page_x, 2, 4],
      0xed => [:sbc, :absolute,    3, 4],
      0xfd => [:sbc, :absolute_x,  3, 4],
      0xf9 => [:sbc, :absolute_y,  3, 4],
      0xe1 => [:sbc, :indirect_x,  2, 6],
      0xf1 => [:sbc, :indirect_y,  2, 5],

      0x38 => [:sec, :implied,     1, 2],
      0xf8 => [:sed, :implied,     1, 2],
      0x78 => [:sei, :implied,     1, 2],

      0x85 => [:sta, :zero_page,   2, 3],
      0x95 => [:sta, :zero_page_x, 2, 4],
      0x8d => [:sta, :absolute,    3, 4],
      0x9d => [:sta, :absolute_x,  3, 5],
      0x99 => [:sta, :absolute_y,  3, 5],
      0x81 => [:sta, :indirect_x,  2, 6],
      0x91 => [:sta, :indirect_y,  2, 6],

      0x86 => [:stx, :zero_page,   2, 3],
      0x96 => [:stx, :zero_page_y, 2, 4],
      0x8e => [:stx, :absolute,    3, 4],

      0x84 => [:sty, :zero_page,   2, 3],
      0x94 => [:sty, :zero_page_x, 2, 4],
      0x8c => [:sty, :absolute,    3, 4],

      0xaa => [:tax, :implied,     1, 2],
      0xa8 => [:tay, :implied,     1, 2],
      0xba => [:tsx, :implied,     1, 2],
      0x8a => [:txa, :implied,     1, 2],
      0x9a => [:txs, :implied,     1, 2],
      0x98 => [:tya, :implied,     1, 2],
    }

    ########################
    #ADDRESSING
    #########################
    def addressing(mode)
      case mode
      when :immediate
        addr = @pc.value + 1
      when :zero_page
        addr = @m.read(@pc.value + 1)
      when :zero_page_x
        addr = @m.read(@pc.value + 1) + @x.value & 0xff
        @m.dummy_read(@pc.value + 2)
      when :zero_page_y
        addr = @m.read(@pc.value + 1) + @y.value & 0xff
        @m.dummy_read(@pc.value + 2)
      when :absolute
        addr = read_u16(@pc.value + 1)
      when :absolute_x
        base_addr = read_u16(@pc.value + 1)
        addr = base_addr + @x.value
        if base_addr & 0xff00 != addr & 0xff00
          @counter += 1
          @m.dummy_read(addr - 0x100)
        end
      when :absolute_y
        base_addr = read_u16(@pc.value + 1)
        addr = base_addr + @y.value
        if base_addr & 0xff00 != addr & 0xff00
          @counter += 1
          @m.dummy_read(addr - 0x100)
        end
      when :indirect
        addr_addr = read_u16(@pc.value + 1)
        addr = read_u16(addr_addr)
      when :indirect_x
        base_addr = @m.read(@pc.value + 1)
        @m.dummy_read(@pc.value + 2)
        addr_addr = (base_addr + @x.value) & 0xff
        addr = read_u16(addr_addr)
      when :indirect_y
        addr_addr = @m.read(@pc.value + 1)
        base_addr = read_u16(addr_addr)
        addr = base_addr + @y.value
        if base_addr & 0xff00 != addr & 0xff00
          @counter += 1
          @m.dummy_read(addr - 0x100)
        end
      when :accumulator
        addr = nil
      when :relative
        addr = @pc.value + 1
      when :implied
        addr = nil
      else
        raise "Unknown Addresing Mode #{mode}"
      end

      return addr
    end

    #########################
    #Deal with flags
    #########################
    def set_carry(result)
      @p.carry = result > 0xff
    end

    def set_zero(result)
      @p.zero = result.zero?
    end

    def set_negative(result)
      @p.negative = result & 0x80 == 0x80
    end

    def set_overflow(bit)
      @p.overflow = bit == 1
    end

    #########################
    #INSTRUCTION SET
    #########################

    #1.ADC
    def adc(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper1 = @m.read(addr)
      oper2 = @a.value

      result = if @p.carry_flag?
                 oper1 + oper2 + 1
               else
                 oper1 + oper2
               end

      @p.overflow = (oper1 & 0x80 == oper2 & 0x80) &&
                    (oper1 & 0x80 != result & 0x80)

      set_carry(result)
      result &= 0xff
      set_zero(result)
      set_negative(result)

      @a.load(result)
      @pc.step(bytes)
      @counter += cycles
    end

    #2.AND
    # named to `und` to avoid conflict with the `and` keyword
    def und(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.read(addr)

      result = oper & @a.value

      set_zero(result)
      set_negative(result)

      @a.load(result)
      @pc.step(bytes)
      @counter += cycles
    end

    #3.ASL
    def asl(addressing_mode, bytes, cycles)
      if addressing_mode == :accumulator
        result = @a.value << 1
        @a.load(result & 0xff)
      else
        addr = addressing(addressing_mode)
        result = @m.read(addr) << 1
        @m.load(addr, result & 0xff)
      end

      set_carry(result)
      set_zero(result & 0xff)
      set_negative(result)

      @pc.step(bytes)
      @counter += cycles
    end

    #4.BCC
    def select_branch(bytes, cycles, test)
      if test
        oper = @m.fetch(@pc.value + 1)
        orig_pc = @pc.value
        @pc.relative_move(oper)
        if @pc.value & 0xff00 != orig_pc & 0xff00
          @counter += 2
        else
          @counter += 1
        end
      end

      @counter += cycles
      @pc.step(bytes)
    end

    def bcc(addressing_mode, bytes, cycles)
      select_branch(bytes, cycles, !@p.carry_flag?)
    end

    #5.BCS
    def bcs(addressing_mode, bytes, cycles)
      select_branch(bytes, cycles, @p.carry_flag?)
    end

    #6.BEQ
    def beq(addressing_mode, bytes, cycles)
      select_branch(bytes, cycles, @p.zero_flag?)
    end

    #7.BIT
    def bit(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)

      result = @a.value & oper
      bit6 = oper >> 6 & 1

      set_zero(result)
      set_negative(oper)
      set_overflow(bit6)

      @counter += cycles
      @pc.step(bytes)
    end

    #8.BMI
    def bmi(addressing_mode, bytes, cycles)
      select_branch(bytes, cycles, @p.negative_flag?)
    end

    #9.BNE
    def bne(addressing_mode, bytes, cycles)
      select_branch(bytes, cycles, !@p.zero_flag?)
    end

    #10.BPL
    def bpl(addressing_mode, bytes, cycles)
      select_branch(bytes, cycles, !@p.negative_flag?)
    end

    #11.BRK
    def push(data)
      #descending stack starts the stack pointer at the end of the array
      #decreases on a push, inreases it on a pull
      @m.load(@sp.value + 0x100, data)
      @sp.add(-1)
    end

    def brk(addressing_mode, bytes, cycles)
      @pc.step
      push(@pc.value >> 8 & 0xff)
      push(@pc.value & 0xff)
      @p.set_break_commond
      push(@p.value)
      @p.disable_interrupt
      @pc.load(@m.fetch(0xfffe) | @m.fetch(0xffff) << 8)
    end

    #12.BVC
    def bvc(addressing_mode, bytes, cycles)
      select_branch(bytes, cycles, !@p.overflow_flag?)
    end

    #13.BVS
    def bvs(addressing_mode, bytes, cycles)
      select_branch(bytes, cycles, @p.overflow_flag?)
    end

    #14.CLC
    def clc(addressing_mode, bytes, cycles)
      @p.clear_carry_flag
      @pc.step bytes
      @counter += cycles
    end

    #15.CLD
    def cld(addressing_mode, bytes, cycles)
      @p.unset_decimal_mode
      @pc.step bytes
      @counter += cycles
    end

    #16.CLI
    def cli(addressing_mode, bytes, cycles)
      @p.enable_interrupt
      @pc.step bytes
      @counter += cycles
    end

    #17.CLV
    def clv(addressing_mode, bytes, cycles)
      @p.clear_overflow_flag
      @pc.step bytes
      @counter += cycles
    end

    #18.CMP
    def cmp(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)
      result = @a.value - oper

      set_zero(result)
      set_negative(result)
      @p.carry = result >= 0

      @pc.step bytes
      @counter += cycles
    end

    #19.CPX
    def cpx(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)
      result = @x.value - oper

      set_zero(result)
      set_negative(result)
      @p.carry = result >= 0

      @pc.step bytes
      @counter += cycles
    end

    #20.CPY
    def cpy(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)
      result = @y.value - oper

      set_zero(result)
      set_negative(result)
      @p.carry = result >= 0

      @pc.step bytes
      @counter += cycles
    end

    #21.DEC
    def dec(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)
      result = (oper - 1) & 0xff

      set_zero(result)
      set_negative(result)

      @m.load(addr, result)
      @pc.step bytes
      @counter += cycles
    end

    #22.DEX
    def dex(addressing_mode, bytes, cycles)
      result = (@x.value - 1) & 0xff

      set_zero(result)
      set_negative(result)

      @x.load(result)
      @pc.step bytes
      @counter += cycles
    end

    #23.DEY
    def dey(addressing_mode, bytes, cycles)
      result = (@y.value - 1) & 0xff

      set_zero(result)
      set_negative(result)

      @y.load(result)
      @pc.step bytes
      @counter += cycles
    end

    #24.EOR
    def eor(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)
      result = @a.value ^ oper

      set_zero(result)
      set_negative(result)
      @a.load(result)
      @pc.step bytes
      @counter += cycles
    end

    #25.INC
    def inc(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)
      result = (oper + 1) & 0xff

      set_zero(result)
      set_negative(result)

      @m.load(addr, result)
      @pc.step bytes
      @counter += cycles
    end

    #26.INX
    def inx(addressing_mode, bytes, cycles)
      result = (@x.value + 1) & 0xff

      set_zero(result)
      set_negative(result)

      @x.load(result)
      @pc.step bytes
      @counter += cycles
    end

    #27.INY
    def iny(addressing_mode, bytes, cycles)
      result = (@y.value + 1) & 0xff

      set_zero(result)
      set_negative(result)

      @y.load(result)
      @pc.step bytes
      @counter += cycles
    end

    #28.JMP
    def jmp(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      @pc.load addr
      @counter += cycles
    end

    #29.JSR
    def jsr(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      return_addr = @pc.value + 2
      push(return_addr >> 8 & 0xff)
      push(return_addr & 0xff)
      @pc.load addr
      @counter += cycles
    end

    #30.LDA
    def lda(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)

      @a.load oper
      set_zero(oper)
      set_negative(oper)

      @pc.step bytes
      @counter += cycles
    end

    #31.LDX
    def ldx(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)

      @x.load oper
      set_zero(oper)
      set_negative(oper)

      @pc.step bytes
      @counter += cycles
    end

    #32.LDY
    def ldy(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)

      @y.load oper
      set_zero(oper)
      set_negative(oper)

      @pc.step bytes
      @counter += cycles
    end

    #33.Logical Shift Right
    def lsr(addressing_mode, bytes, cycles)
      if addressing_mode == :accumulator
        result = @a.value >> 1
        @p.carry = @a.value & 1 == 1
        @a.load result
      else
        addr = self.addressing(addressing_mode)
        oper = @m.fetch(addr)
        @p.carry = oper & 1 == 1
        result = oper >> 1
        @m.load(addr, result)
      end

      set_zero(result)
      set_negative(result)

      @pc.step bytes
      @counter += cycles
    end

    #34.NOP
    def nop(addressing_mode, bytes, cycles)
      @pc.step bytes
      @counter += cycles
    end

    #35.ORA
    def ora(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper = @m.fetch(addr)
      result = @a.value | oper

      set_zero(result)
      set_negative(result)
      @a.load(result)
      @pc.step bytes
      @counter += cycles
    end

    #36.PHA
    def pha(addressing_mode, bytes, cycles)
      self.push @a.value

      @pc.step bytes
      @counter += cycles
    end

    #37.PHP
    def php(addressing_mode, bytes, cycles)
      @p.set_break_commond
      self.push @p.value | 0x20

      @pc.step bytes
      @counter += cycles
    end

    #38.PLA
    def pull
      #empty stack, SP moves before pull
      @sp.add 1
      a = @m.fetch(@sp.value + 0x100)   
      return a
    end

    def pla(addressing_mode, bytes, cycles)
      @a.load(self.pull)

      set_zero(@a.value)
      set_negative(@a.value)
      @pc.step bytes
      @counter += cycles
    end

    #39.PLP
    def plp(addressing_mode, bytes, cycles)
      @p.load(self.pull | 0x20)

      @pc.step bytes
      @counter += cycles
    end

    #40.Rotate Left
    def rol(addressing_mode, bytes, cycles)
      if addressing_mode == :accumulator
        result = @a.value << 1 | (@p.value & 0x1)
        @a.load(result & 0xff)
      else
        addr = addressing(addressing_mode)
        result = @m.read(addr) << 1 | (@p.value & 0x1)
        @m.load(addr, result & 0xff)
      end

      set_carry(result)
      set_zero(result & 0xff)
      set_negative(result)

      @pc.step(bytes)
      @counter += cycles
    end

    #41.Rotate Right
    def ror(addressing_mode, bytes, cycles)
      if addressing_mode == :accumulator
        result = (@p.value & 1) << 7 | @a.value >> 1
        @p.carry = @a.value & 1 == 1
        @a.load(result)
      else
        addr = self.addressing(addressing_mode)
        data = @m.fetch(addr)
        result = (@p.value & 1) << 7 | data >> 1
        @p.carry = data & 1 == 1
        @m.load(addr, result)
      end

      set_zero(result)
      set_negative(result)

      @pc.step bytes
      @counter += cycles
    end

    #42.RTI
    def rti(addressing_mode, bytes, cycles)
      @p.load(self.pull | 0x20)
      addr_low = self.pull
      addr_high = self.pull
      @pc.load(addr_high << 8 | addr_low)

      @counter += cycles
    end

    #43.RTS
    def rts(addressing_mode, bytes, cycles)
      addr_low = self.pull
      addr_high = self.pull
      @pc.load(addr_high << 8 | addr_low)
      @pc.step

      @counter += cycles
    end

    #44.Subtract with Carry
    def sbc(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      oper1 = @a.value
      oper2 = @m.fetch(addr)

      result = oper1 + (oper2 ^ 0xff) + (@p.carry_flag? ? 1 : 0)

      set_carry(result)
      set_zero(result & 0xff)
      set_negative(result & 0xff)

      @p.overflow = (oper1 & 0x80 != oper2 & 0x80) &&
                    (oper1 & 0x80 != result & 0x80)

      @a.load(result & 0xff)
      @pc.step bytes
      @counter += cycles
    end

    #45.SEC
    def sec(addressing_mode, bytes, cycles)
      @p.set_carry_flag
      @pc.step bytes
      @counter += cycles
    end

    #46.SED
    def sed(addressing_mode, bytes, cycles)
      @p.set_decimal_mode
      @pc.step bytes
      @counter += cycles
    end

    #47.SEI
    def sei(addressing_mode, bytes, cycles)
      @p.disable_interrupt
      @pc.step bytes
      @counter += cycles
    end

    #48.Store the Accumulator in Memory
    def sta(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      @m.load(addr, @a.value)

      @pc.step bytes
      @counter += cycles
    end

    #49.STX
    def stx(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      @m.load(addr, @x.value)

      @pc.step bytes
      @counter += cycles
    end

    #50.STY
    def sty(addressing_mode, bytes, cycles)
      addr = self.addressing(addressing_mode)
      @m.load(addr, @y.value)

      @pc.step bytes
      @counter += cycles
    end

    #51.TAX
    def tax(addressing_mode, bytes, cycles)
      @x.load(@a.value)

      set_zero(@x.value)
      set_negative(@x.value)

      @pc.step bytes
      @counter += cycles
    end

    #52.TAY
    def tay(addressing_mode, bytes, cycles)
      @y.load(@a.value)

      set_zero(@y.value)
      set_negative(@y.value)

      @pc.step bytes
      @counter += cycles
    end

    #53.TSX
    def tsx(addressing_mode, bytes, cycles)
      @x.load(@sp.value)

      set_zero(@x.value)
      set_negative(@x.value)

      @pc.step bytes
      @counter += cycles
    end

    #54.TXA
    def txa(addressing_mode, bytes, cycles)
      @a.load(@x.value)

      set_zero(@a.value)
      set_negative(@a.value)

      @pc.step bytes
      @counter += cycles
    end

    #55.TXS
    def txs(addressing_mode, bytes, cycles)
      @sp.load(@x.value)

      @pc.step bytes
      @counter += cycles
    end

    #56.TYA
    def tya(addressing_mode, bytes, cycles)
      @a.load(@y.value)

      set_zero(@a.value)
      set_negative(@a.value)

      @pc.step bytes
      @counter += cycles
    end

    def self.unknown_op
      "raise \"Unkown op code \#{op}\""
    end

    # generate a method call from the array returned from `decode`
    # args: [method, address_mode, bytes, cycles]
    def self.send_args(args)
      method, addr_mode, bytes, cy = *args
      "#{method}(:#{addr_mode}, #{bytes}, #{cy})"
    end

    def self.static_method_call
      defination = "case op\n"
      (0..255).each do |i|
        if c = OP_TABLE[i]
          defination += "when #{i} then #{send_args(c)}\n"
        end
      end
      defination += "else #{unknown_op} end"
    end

    defination = static_method_call

    class_eval("def run(op); #{defination} end")
  end
end
