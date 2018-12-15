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

  class StatusRegister < Register
    def carry_flag?
      @value & 0x1 == 0x1
    end

    def set_carry_flag
      @value |= 0x1
    end

    def clear_carry_flag
      @value &= 0xfe
    end

    def zero_flag?
      @value & 0x2 == 0x2
    end

    def set_zero_flag
      @value |= 0x2
    end

    def clear_zero_flag
      @value &= 0xfd
    end

    def interrupt_disabled?
      @value & 0x4 == 0x4
    end

    def disable_interrupt
      @value |= 0x4
    end

    def enable_interrupt
      @value &= 0xfb
    end

    def decimal_mode?
      @value & 0x8 == 0x8
    end

    def set_decimal_mode
      @value |= 0x8
    end

    def unset_decimal_mode
      @value &= 0xf7
    end

    def break_commond?
      @value & 0x10 == 0x10
    end

    def set_break_commond
      @value |= 0x10
    end

    def unset_break_commond
      @value &= 0xef
    end

    def overflow_flag?
      @value & 0x40 == 0x40
    end

    def set_overflow_flag
      @value |= 0x40
    end

    def clear_overflow_flag
      @value &= 0xbf
    end

    def negative_flag?
      @value & 0x80 == 0x80
    end

    def set_negative_flag
      @value |= 0x80
    end

    def clear_negative_flag
      @value &= 0x7f
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
    def accumulator
      @a.value
    end

    def x_register
      @x.value
    end

    def y_register
      @y.value
    end

    def pc
      @pc.value
    end

    def p_register
      @p.value
    end

    def stack_pointer
      @sp.value
    end

    def mem
      @m
    end

    def cycle
      @counter
    end

    #########################
    #OPCODES
    #########################
    def self.decode(opcode)
      case opcode
      when 0x69 then [:adc, :immediate,   2, 2]
      when 0x65 then [:adc, :zero_page,   2, 3]
      when 0x75 then [:adc, :zero_page_x, 2, 4]
      when 0x6d then [:adc, :absolute,    3, 4]
      when 0x7d then [:adc, :absolute_x,  3, 4]
      when 0x79 then [:adc, :absolute_y,  3, 4]
      when 0x61 then [:adc, :indirect_x,  2, 6]
      when 0x71 then [:adc, :indirect_y,  2, 5]

      when 0x29 then [:and_, :immediate,   2, 2]
      when 0x25 then [:and_, :zero_page,   2, 3]
      when 0x35 then [:and_, :zero_page_x, 2, 4]
      when 0x2d then [:and_, :absolute,    3, 4]
      when 0x3d then [:and_, :absolute_x,  3, 4]
      when 0x39 then [:and_, :absolute_y,  3, 4]
      when 0x21 then [:and_, :indirect_x,  2, 6]
      when 0x31 then [:and_, :indirect_y,  2, 5]

      when 0x0a then [:asl, :accumulator, 1, 2]
      when 0x06 then [:asl, :zero_page,   2, 5]
      when 0x16 then [:asl, :zero_page_x, 2, 6]
      when 0x0e then [:asl, :absolute,    3, 6]
      when 0x1e then [:asl, :absolute_x,  3, 7]

      when 0x90 then [:bcc, :relative,    2, 2]
      when 0xb0 then [:bcs, :relative,    2, 2]
      when 0xf0 then [:beq, :relative,    2, 2]

      when 0x24 then [:bit, :zero_page,   2, 3]
      when 0x2c then [:bit, :absolute,    3, 4]

      when 0x30 then [:bmi, :relative,    2, 2]
      when 0xd0 then [:bne, :relative,    2, 2]
      when 0x10 then [:bpl, :relative,    2, 2]
      when 0x00 then [:brk, :implied,     1, 7]
      when 0x50 then [:bvc, :relative,    2, 2]
      when 0x70 then [:bvs, :relative,    2, 2]
      when 0x18 then [:clc, :implied,     1, 2]
      when 0xd8 then [:cld, :implied,     1, 2]
      when 0x58 then [:cli, :implied,     1, 2]
      when 0xb8 then [:clv, :implied,     1, 2]

      when 0xc9 then [:cmp, :immediate,   2, 2]
      when 0xc5 then [:cmp, :zero_page,   2, 3]
      when 0xd5 then [:cmp, :zero_page_x, 2, 4]
      when 0xcd then [:cmp, :absolute,    3, 4]
      when 0xdd then [:cmp, :absolute_x,  3, 4]
      when 0xd9 then [:cmp, :absolute_y,  3, 4]
      when 0xc1 then [:cmp, :indirect_x,  2, 6]
      when 0xd1 then [:cmp, :indirect_y,  2, 5]

      when 0xe0 then [:cpx, :immediate,   2, 2]
      when 0xe4 then [:cpx, :zero_page,   2, 3]
      when 0xec then [:cpx, :absolute,    3, 4]

      when 0xc0 then [:cpy, :immediate,   2, 2]
      when 0xc4 then [:cpy, :zero_page,   2, 3]
      when 0xcc then [:cpy, :absolute,    3, 4]

      when 0xc6 then [:dec, :zero_page,   2, 5]
      when 0xd6 then [:dec, :zero_page_x, 2, 6]
      when 0xce then [:dec, :absolute,    3, 6]
      when 0xde then [:dec, :absolute_x,  3, 7]

      when 0xca then [:dex, :implied,     1, 2]
      when 0x88 then [:dey, :implied,     1, 2]

      when 0x49 then [:eor, :immediate,   2, 2]
      when 0x45 then [:eor, :zero_page,   2, 3]
      when 0x55 then [:eor, :zero_page_x, 2, 4]
      when 0x4d then [:eor, :absolute,    3, 4]
      when 0x5d then [:eor, :absolute_x,  3, 4]
      when 0x59 then [:eor, :absolute_y,  3, 4]
      when 0x41 then [:eor, :indirect_x,  2, 6]
      when 0x51 then [:eor, :indirect_y,  2, 5]

      when 0xe6 then [:inc, :zero_page,   2, 5]
      when 0xf6 then [:inc, :zero_page_x, 2, 6]
      when 0xee then [:inc, :absolute,    3, 6]
      when 0xfe then [:inc, :absolute_x,  3, 7]

      when 0xe8 then [:inx, :implied,     1, 2]
      when 0xc8 then [:iny, :implied,     1, 2]

      when 0x4c then [:jmp, :absolute,    3, 3]
      when 0x6c then [:jmp, :indirect,    3, 5]

      when 0x20 then [:jsr, :absolute,    3, 6]

      when 0xa9 then [:lda, :immediate,   2, 2]
      when 0xa5 then [:lda, :zero_page,   2, 3]
      when 0xb5 then [:lda, :zero_page_x, 2, 4]
      when 0xad then [:lda, :absolute,    3, 4]
      when 0xbd then [:lda, :absolute_x,  3, 4]
      when 0xb9 then [:lda, :absolute_y,  3, 4]
      when 0xa1 then [:lda, :indirect_x,  2, 6]
      when 0xb1 then [:lda, :indirect_y,  2, 5]

      when 0xa2 then [:ldx, :immediate,   2, 2]
      when 0xa6 then [:ldx, :zero_page,   2, 3]
      when 0xb6 then [:ldx, :zero_page_y, 2, 4]
      when 0xae then [:ldx, :absolute,    3, 4]
      when 0xbe then [:ldx, :absolute_y,  3, 4]

      when 0xa0 then [:ldy, :immediate,   2, 2]
      when 0xa4 then [:ldy, :zero_page,   2, 3]
      when 0xb4 then [:ldy, :zero_page_x, 2, 4]
      when 0xac then [:ldy, :absolute,    3, 4]
      when 0xbc then [:ldy, :absolute_x,  3, 4]

      when 0x4a then [:lsr, :accumulator, 1, 2]
      when 0x46 then [:lsr, :zero_page,   2, 5]
      when 0x56 then [:lsr, :zero_page_x, 2, 4]
      when 0x4e then [:lsr, :absolute,    3, 4]
      when 0x5e then [:lsr, :absolute_x,  3, 7]

      when 0xea then [:nop, :implied,     1, 2]

      when 0x09 then [:ora, :immediate,   2, 2]
      when 0x05 then [:ora, :zero_page,   2, 3]
      when 0x15 then [:ora, :zero_page_x, 2, 4]
      when 0x0d then [:ora, :absolute,    3, 4]
      when 0x1d then [:ora, :absolute_x,  3, 4]
      when 0x19 then [:ora, :absolute_y,  3, 4]
      when 0x01 then [:ora, :indirect_x,  2, 6]
      when 0x11 then [:ora, :indirect_y,  2, 5]

      when 0x48 then [:pha, :implied,     1, 3]
      when 0x08 then [:php, :implied,     1, 3]
      when 0x68 then [:pla, :implied,     1, 4]
      when 0x28 then [:plp, :implied,     1, 4]

      when 0x2a then [:rol, :accumulator, 1, 2]
      when 0x26 then [:rol, :zero_page,   2, 5]
      when 0x36 then [:rol, :zero_page_x, 2, 6]
      when 0x2e then [:rol, :absolute,    3, 6]
      when 0x3e then [:rol, :absolute_x,  3, 7]

      when 0x6a then [:ror, :accumulator, 1, 2]
      when 0x66 then [:ror, :zero_page,   2, 5]
      when 0x76 then [:ror, :zero_page_x, 2, 6]
      when 0x6e then [:ror, :absolute,    3, 6]
      when 0x7e then [:ror, :absolute_x,  3, 7]

      when 0x40 then [:rti, :implied,     1, 6]
      when 0x60 then [:rts, :implied,     1, 6]

      when 0xe9 then [:sbc, :immediate,   2, 2]
      when 0xe5 then [:sbc, :zero_page,   2, 3]
      when 0xf5 then [:sbc, :zero_page_x, 2, 4]
      when 0xed then [:sbc, :absolute,    3, 4]
      when 0xfd then [:sbc, :absolute_x,  3, 4]
      when 0xf9 then [:sbc, :absolute_y,  3, 4]
      when 0xe1 then [:sbc, :indirect_x,  2, 6]
      when 0xf1 then [:sbc, :indirect_y,  2, 5]

      when 0x38 then [:sec, :implied,     1, 2]
      when 0xf8 then [:sed, :implied,     1, 2]
      when 0x78 then [:sei, :implied,     1, 2]

      when 0x85 then [:sta, :zero_page,   2, 3]
      when 0x95 then [:sta, :zero_page_x, 2, 4]
      when 0x8d then [:sta, :absolute,    3, 4]
      when 0x9d then [:sta, :absolute_x,  3, 5]
      when 0x99 then [:sta, :absolute_y,  3, 5]
      when 0x81 then [:sta, :indirect_x,  2, 6]
      when 0x91 then [:sta, :indirect_y,  2, 6]

      when 0x86 then [:stx, :zero_page,   2, 3]
      when 0x96 then [:stx, :zero_page_y, 2, 4]
      when 0x8e then [:stx, :absolute,    3, 4]

      when 0x84 then [:sty, :zero_page,   2, 3]
      when 0x94 then [:sty, :zero_page_x, 2, 4]
      when 0x8c then [:sty, :absolute,    3, 4]

      when 0xaa then [:tax, :implied,     1, 2]
      when 0xa8 then [:tay, :implied,     1, 2]
      when 0xba then [:tsx, :implied,     1, 2]
      when 0x8a then [:txa, :implied,     1, 2]
      when 0x9a then [:txs, :implied,     1, 2]
      when 0x98 then [:tya, :implied,     1, 2]

      end
    end

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
      when :zero_page_y
        addr = @m.read(@pc.value + 1) + @y.value & 0xff
      when :absolute
        addr = @m.read(@pc.value + 1) | @m.read(@pc.value + 2) << 8
      when :absolute_x
        addr = @m.read(@pc.value + 1) | @m.read(@pc.value + 2) << 8
        if addr & 0xff00 != (addr + @x.value) & 0xff00
          @counter += 1
        end
        addr += @x.value
      when :absolute_y
        addr = @m.read(@pc.value + 1) | @m.read(@pc.value + 2) << 8
        if addr & 0xff00 != (addr + @y.value) & 0xff00
          @counter += 1
        end
        addr += @y.value
      when :indirect
        addr = @m.read(@pc.value + 1) | @m.read(@pc.value + 2) << 8
        addr = @m.read(addr) | @m.read(addr + 1) << 8
      when :indirect_x
        addr = @m.read(@pc.value + 1)
        addr = (addr + @x.value) & 0xff
        addr = @m.read(addr) | @m.read(addr + 1) << 8
      when :indirect_y
        addr = @m.read(@pc.value + 1)
        addr = @m.read(addr) | @m.read(addr + 1) << 8
        if addr & 0xff00 != (addr + @y.value) & 0xff00
          @counter += 1
        end
        addr += @y.value
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
      if result > 0xff
        @p.set_carry_flag
      else
        @p.clear_carry_flag
      end
    end

    def set_zero(result)
      if result == 0
        @p.set_zero_flag
      else
        @p.clear_zero_flag
      end
    end

    def set_negative(result)
      if result & 0x80 == 0x80
        @p.set_negative_flag
      else
        @p.clear_negative_flag
      end
    end

    def set_overflow(bit)
      if bit == 1
        @p.set_overflow_flag
      else
        @p.clear_overflow_flag
      end
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

      if (oper1 & 0x80 == oper2 & 0x80) &&
         (oper1 & 0x80 != result & 0x80)
        @p.set_overflow_flag
      else
        @p.clear_overflow_flag
      end

      set_carry(result)
      result &= 0xff
      set_zero(result)
      set_negative(result)

      @a.load(result)
      @pc.step(bytes)
      @counter += cycles
    end

    #2.AND
    # Add an underscore to avoid conflict with the `and` keyword
    def and_(addressing_mode, bytes, cycles)
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
    def select_branch(addressing_mode, bytes, cycles)
      if yield
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
      select_branch(addressing_mode, bytes, cycles) { !@p.carry_flag? }
    end

    #5.BCS
    def bcs(addressing_mode, bytes, cycles)
      select_branch(addressing_mode, bytes, cycles) { @p.carry_flag? }
    end

    #6.BEQ
    def beq(addressing_mode, bytes, cycles)
      select_branch(addressing_mode, bytes, cycles) { @p.zero_flag? }
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
      select_branch(addressing_mode, bytes, cycles) { @p.negative_flag? }
    end

    #9.BNE
    def bne(addressing_mode, bytes, cycles)
      select_branch(addressing_mode, bytes, cycles) { !@p.zero_flag? }
    end

    #10.BPL
    def bpl(addressing_mode, bytes, cycles)
      select_branch(addressing_mode, bytes, cycles) { !@p.negative_flag? }
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
      select_branch(addressing_mode, bytes, cycles) { !@p.overflow_flag? }
    end

    #13.BVS
    def bvs(addressing_mode, bytes, cycles)
      select_branch(addressing_mode, bytes, cycles) { @p.overflow_flag? }
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
      if result >= 0
        @p.set_carry_flag
      else
        @p.clear_carry_flag
      end

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
      if result >= 0
        @p.set_carry_flag
      else
        @p.clear_carry_flag
      end

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
      if result >= 0
        @p.set_carry_flag
      else
        @p.clear_carry_flag
      end

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
        if @a.value & 1 == 1
          @p.set_carry_flag
        else
          @p.clear_carry_flag
        end
        @a.load result
      else
        addr = self.addressing(addressing_mode)
        oper = @m.fetch(addr)
        if oper & 1 == 1
          @p.set_carry_flag
        else
          @p.clear_carry_flag
        end
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
        if @a.value & 1 == 1
          @p.set_carry_flag
        else
          @p.clear_carry_flag
        end
        @a.load(result)
      else
        addr = self.addressing(addressing_mode)
        data = @m.fetch(addr)
        result = (@p.value & 1) << 7 | data >> 1
        if data & 1 == 1
          @p.set_carry_flag
        else
          @p.clear_carry_flag
        end
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

      if (oper1 & 0x80 != oper2 & 0x80) &&
         (oper1 & 0x80 != result & 0x80)
        @p.set_overflow_flag
      else
        @p.clear_overflow_flag
      end

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

    # From here, define a binary search version of `decode`
    #
    def self.unknown_op
      "raise \"Unkown op code \#{op}\""
    end

    # generate a method call from the array returned from `decode`
    # args: [method, address_mode, bytes, cycles]
    def self.send_args(args)
      method, addr_mode, bytes, cy = *args
      "#{method}(:#{addr_mode}, #{bytes}, #{cy})"
    end

    def self.binary_search_opcode(top, bottom)
      if top <= bottom
        raise "Illegal arguments, top should be greater than bottom, but top = #{top} bottom = #{bottom}"
      end

      if top - bottom == 1 # The base case
        top_branch = decode(top)
        bottom_branch = decode(bottom)
        if top_branch.nil? && bottom_branch.nil?
          # Both opcode are unknown
          unknown_op
        elsif top_branch.nil?
          "if op == #{bottom} then #{send_args(bottom_branch)} else #{unknown_op} end"
        elsif bottom_branch.nil?
          "if op == #{top} then #{send_args(top_branch)} else #{unknown_op} end"
        else
          "if op == #{top} then #{send_args(top_branch)} else #{send_args(bottom_branch)} end"
        end
      else # Recursive defination
        mid = (top + bottom) / 2
        "if op > #{mid}\n"\
          "#{binary_search_opcode(top, mid + 1)}\n"\
        "else\n"\
          "#{binary_search_opcode(mid, bottom)}\n"\
        "end"
      end
    end

    def self.static_method_call
      defination = "case op\n"
      (0..255).each do |i|
        if c = decode(i)
          defination += "when #{i} then #{send_args(c)}\n"
        end
      end
      defination += "else #{unknown_op} end"
    end

    #defination = binary_search_opcode(255, 0)
    defination = static_method_call

    class_eval("def run(op); #{defination} end")
  end
end
