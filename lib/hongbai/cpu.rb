module Hongbai
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

    attr_accessor :carry, :zero, :overflow, :negative, :break,
      :disable_interrupt, :decimal_mode

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
  end

  class Cpu
    NMI_VECTOR = 0xfffa
    BRK_VECTOR = 0xfffe
    RESET_VECTOR = 0xfffc

    def initialize(mem)
      @m = mem
      @a = 0 #Accumulator Register
      @x = 0 #Index Register X
      @y = 0 #Index Register Y
      @sp = 0xfd #Stack Pointer
      @p = StatusRegister.new
      @p.load(0x34)
      @pc = read_u16(RESET_VECTOR)
      @m.reset

      @operand_addr = nil
      @address_carry = nil
      @trace = false
    end

    attr_accessor :trace

    def step
      opcode = @m.fetch(@pc)
      op, addressing, _bytes, _cycles = *OP_TABLE[opcode]
      send addressing
      send op
    end

    def nmi
      @m.dummy_read @pc
      @m.dummy_read @pc
      push(@pc >> 8)
      push(@pc & 0xff)
      push(@p.value)
      @p.disable_interrupt = true
      @pc = read_u16(NMI_VECTOR)
    end

    def irq
      return if interrupt_disabled?

      @m.dummy_read @pc
      @m.dummy_read @pc
      push(@pc >> 8)
      push(@pc & 0xff)
      push(@p.value)
      @p.disable_interrupt = true
      @pc = read_u16(BRK_VECTOR)
    end

    def read_u16(addr)
      lo = @m.read(addr)
      hi = @m.read(addr + 1)
      (hi << 8) | lo
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
      0x56 => [:lsr, :zero_page_x, 2, 6],
      0x4e => [:lsr, :absolute,    3, 6],
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
    def immediate
      @operand_addr = @pc + 1
      @pc += 2
    end

    def zero_page
      @operand_addr = @m.read(@pc + 1)
      @pc += 2
    end

    def zero_page_x
      base_addr = @m.read(@pc + 1)
      @pc += 2
      @m.dummy_read(@pc)
      @operand_addr = (base_addr + @x) & 0xff
    end

    def zero_page_y
      base_addr = @m.read(@pc + 1)
      @pc += 2
      @m.dummy_read(@pc)
      @operand_addr = (base_addr + @y) & 0xff
    end

    def absolute
      @operand_addr = read_u16(@pc + 1)
      @pc += 3
    end

    def absolute_x
      lo = @m.read(@pc + 1)
      hi = @m.read(@pc + 2) << 8
      sum = lo + @x
      @operand_addr = hi | (sum & 0xff)
      @address_carry = sum > 0xff
      @pc += 3
    end

    def absolute_y
      lo = @m.read(@pc + 1)
      hi = @m.read(@pc + 2) << 8
      sum = lo + @y
      @operand_addr = hi | (sum & 0xff)
      @address_carry = sum > 0xff
      @pc += 3
    end

    def indirect
      addr_addr = read_u16(@pc + 1)
      @operand_addr = read_u16(addr_addr)
      @pc += 3
    end

    def indirect_x
      base_addr = @m.read(@pc + 1)
      @pc += 2
      @m.dummy_read(@pc)
      addr_addr = (base_addr + @x) & 0xff
      @operand_addr = read_u16(addr_addr)
    end

    def indirect_y
      addr_addr = @m.read(@pc + 1)
      @pc += 2
      lo = @m.read(addr_addr)
      hi = @m.read(addr_addr + 1) << 8
      sum = lo + @y
      @operand_addr = hi | (sum & 0xff)
      @address_carry = sum > 0xff
    end

    def accumulator
      @pc += 1
      @m.dummy_read(@pc)
      @operand_addr = nil
    end

    def relative
      @pc += 1
      @operand_addr = @pc
    end

    def implied
      @pc += 1
      @m.dummy_read(@pc)
      @operand_addr = nil
    end

    def fix_address
      @m.read(@operand_addr)
      @operand_addr = (@operand_addr + 0x100) & 0xffff if @address_carry
      @address_carry = nil
    end

    def read_or_fix_read
      val = @m.read(@operand_addr)
      if @address_carry.nil?
        return val
      elsif @address_carry
        @operand_addr = (@operand_addr + 0x100) & 0xffff
        val = @m.read(@operand_addr)
      end
      @address_carry = nil
      val
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
    # Helper functions
    # #######################

    # Read-Modify-Write instructions write the original value back first then
    # write the new value
    def update(orig_val, val)
      @m.load(@operand_addr, orig_val)
      @m.load(@operand_addr, val)
    end

    def push(data)
      #descending stack starts the stack pointer at the end of the array
      #decreases on a push, inreases it on a pull
      @m.load(@sp + 0x100, data)
      @sp -= 1
    end

    def pull
      #empty stack, SP moves before pull
      @sp += 1
      @m.fetch(@sp + 0x100)   
    end

    def stack_dummy_read
      @m.dummy_read(@sp + 0x100)
    end

    #########################
    #INSTRUCTION SET
    #########################

    #1.ADC
    def adc
      oper1 = read_or_fix_read
      oper2 = @a

      result = if @p.carry
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

      @a = result
    end

    #2.AND
    # named to `und` to avoid conflict with the `and` keyword
    def und
      oper = read_or_fix_read
      @a &= oper

      set_zero(@a)
      set_negative(@a)
    end

    #3.ASL
    def asl
      if @operand_addr.nil?
        result = @a << 1
        @a = result & 0xff
      else
        fix_address unless @address_carry.nil?
        oper = @m.read(@operand_addr)
        result = oper << 1
        update(oper, result & 0xff)
      end

      set_carry(result)
      set_zero(result & 0xff)
      set_negative(result)
    end

    #4.BCC
    def select_branch(test)
      oper = @m.read(@operand_addr)
      @pc += 1
      if test
        orig_pc = @pc
        @m.dummy_read @pc
        @pc += oper > 127 ? oper - 256 : oper
        if @pc & 0xff00 != orig_pc & 0xff00
          @m.dummy_read(@pc - 0x100)
        end
      end
    end

    def bcc
      select_branch(!@p.carry)
    end

    #5.BCS
    def bcs
      select_branch(@p.carry)
    end

    #6.BEQ
    def beq
      select_branch(@p.zero)
    end

    #7.BIT
    def bit
      oper = @m.fetch(@operand_addr)

      result = @a & oper
      bit6 = oper >> 6 & 1

      set_zero(result)
      set_negative(oper)
      set_overflow(bit6)
    end

    #8.BMI
    def bmi
      select_branch(@p.negative)
    end

    #9.BNE
    def bne
      select_branch(!@p.zero)
    end

    #10.BPL
    def bpl
      select_branch(!@p.negative)
    end

    #11.BRK
    def brk
      push(@pc >> 8 & 0xff)
      push(@pc & 0xff)
      @p.break = true
      push(@p.value)
      @p.disable_interrupt = true
      @pc = read_u16(BRK_VECTOR)
    end

    #12.BVC
    def bvc
      select_branch(!@p.overflow)
    end

    #13.BVS
    def bvs
      select_branch(@p.overflow)
    end

    #14.CLC
    def clc
      @p.carry = false
    end

    #15.CLD
    def cld
      @p.decimal_mode = false
    end

    #16.CLI
    def cli
      @p.disable_interrupt = false
    end

    #17.CLV
    def clv
      @p.overflow = false
    end

    #18.CMP
    def cmp
      oper = read_or_fix_read
      result = @a - oper

      set_zero(result)
      set_negative(result)
      @p.carry = result >= 0
    end

    #19.CPX
    def cpx
      oper = @m.fetch(@operand_addr)
      result = @x - oper

      set_zero(result)
      set_negative(result)
      @p.carry = result >= 0
    end

    #20.CPY
    def cpy
      oper = @m.fetch(@operand_addr)
      result = @y - oper

      set_zero(result)
      set_negative(result)
      @p.carry = result >= 0
    end

    #21.DEC
    def dec
      fix_address unless @address_carry.nil?
      oper = @m.fetch(@operand_addr)
      result = (oper - 1) & 0xff

      set_zero(result)
      set_negative(result)

      update(oper, result)
    end

    #22.DEX
    def dex
      result = (@x - 1) & 0xff

      set_zero(result)
      set_negative(result)

      @x = result
    end

    #23.DEY
    def dey
      result = (@y - 1) & 0xff

      set_zero(result)
      set_negative(result)

      @y = result
    end

    #24.EOR
    def eor
      oper = read_or_fix_read
      result = @a ^ oper

      set_zero(result)
      set_negative(result)
      @a = result
    end

    #25.INC
    def inc
      fix_address unless @address_carry.nil?
      oper = @m.fetch(@operand_addr)
      result = (oper + 1) & 0xff

      set_zero(result)
      set_negative(result)

      update(oper, result)
    end

    #26.INX
    def inx
      result = (@x + 1) & 0xff

      set_zero(result)
      set_negative(result)

      @x = result
    end

    #27.INY
    def iny
      result = (@y + 1) & 0xff

      set_zero(result)
      set_negative(result)

      @y = result
    end

    #28.JMP
    def jmp
      @pc = @operand_addr
    end

    #29.JSR
    def jsr
      return_addr = @pc - 1
      stack_dummy_read
      push(return_addr >> 8 & 0xff)
      push(return_addr & 0xff)
      @pc = @operand_addr 
    end

    #30.LDA
    def lda
      oper = read_or_fix_read

      @a = oper
      set_zero(oper)
      set_negative(oper)
    end

    #31.LDX
    def ldx
      oper = read_or_fix_read

      @x = oper
      set_zero(oper)
      set_negative(oper)
    end

    #32.LDY
    def ldy
      oper = read_or_fix_read

      @y = oper
      set_zero(oper)
      set_negative(oper)
    end

    #33.Logical Shift Right
    def lsr
      if @operand_addr.nil?
        result = @a >> 1
        @p.carry = @a & 1 == 1
        @a = result
      else
        fix_address unless @address_carry.nil?
        oper = @m.fetch(@operand_addr)
        @p.carry = oper & 1 == 1
        result = oper >> 1
        update(oper, result)
      end

      set_zero(result)
      set_negative(result)
    end

    #34.NOP
    def nop; nil end

    #35.ORA
    def ora
      oper = read_or_fix_read
      result = @a | oper

      set_zero(result)
      set_negative(result)
      @a = result
    end

    #36.PHA
    def pha
      push @a
    end

    #37.PHP
    def php
      @p.break = true
      push @p.value
    end

    #38.PLA
    def pla
      stack_dummy_read
      @a = self.pull

      set_zero(@a)
      set_negative(@a)
    end

    #39.PLP
    def plp
      stack_dummy_read
      @p.load(self.pull)
    end

    #40.Rotate Left
    def rol
      if @operand_addr.nil?
        result = @a << 1 | (@p.carry ? 1 : 0)
        @a = result & 0xff
      else
        fix_address unless @address_carry.nil?
        oper = @m.read(@operand_addr)
        result = oper << 1 | (@p.carry ? 1 : 0)
        update(oper, result & 0xff)
      end

      set_carry(result)
      set_zero(result & 0xff)
      set_negative(result)
    end

    #41.Rotate Right
    def ror
      if @operand_addr.nil?
        result = (@p.value & 1) << 7 | @a >> 1
        @p.carry = @a & 1 == 1
        @a = result
      else
        fix_address unless @address_carry.nil?
        data = @m.fetch(@operand_addr)
        result = (@p.value & 1) << 7 | data >> 1
        @p.carry = data & 1 == 1
        update(data, result)
      end

      set_zero(result)
      set_negative(result)
    end

    #42.RTI
    def rti
      stack_dummy_read
      @p.load(self.pull)
      addr_low = self.pull
      addr_high = self.pull
      @pc = addr_high << 8 | addr_low
    end

    #43.RTS
    def rts
      stack_dummy_read
      addr_low = self.pull
      addr_high = self.pull
      @pc = addr_high << 8 | addr_low
      @m.dummy_read(@pc)
      @pc += 1
    end

    #44.Subtract with Carry
    def sbc
      oper1 = @a
      oper2 = read_or_fix_read

      result = oper1 + (oper2 ^ 0xff) + (@p.carry ? 1 : 0)

      set_carry(result)
      set_zero(result & 0xff)
      set_negative(result & 0xff)

      @p.overflow = (oper1 & 0x80 != oper2 & 0x80) &&
                    (oper1 & 0x80 != result & 0x80)

      @a = result & 0xff
    end

    #45.SEC
    def sec
      @p.carry = true
    end

    #46.SED
    def sed
      @p.decimal_mode = true
    end

    #47.SEI
    def sei
      @p.disable_interrupt = true
    end

    #48.Store the Accumulator in Memory
    def sta
      fix_address unless @address_carry.nil?
      @m.load(@operand_addr, @a)
    end

    #49.STX
    def stx
      @m.load(@operand_addr, @x)
    end

    #50.STY
    def sty
      @m.load(@operand_addr, @y)
    end

    #51.TAX
    def tax
      @x = @a

      set_zero(@x)
      set_negative(@x)
    end

    #52.TAY
    def tay
      @y = @a

      set_zero(@y)
      set_negative(@y)
    end

    #53.TSX
    def tsx
      @x = @sp

      set_zero(@x)
      set_negative(@x)
    end

    #54.TXA
    def txa
      @a = @x

      set_zero(@a)
      set_negative(@a)
    end

    #55.TXS
    def txs
      @sp = @x
    end

    #56.TYA
    def tya
      @a = @y

      set_zero(@a)
      set_negative(@a)
    end

    def self.unknown_op
      "raise \"Unkown op code \#{op}\""
    end

    # generate a method call from the array returned from `decode`
    # args: [method, address_mode, bytes, cycles]
    def self.send_args(args)
      method, _, _bytes, _cy = *args
      "#{method}"
    end

    def self.static_method_call
      defination = "case op\n"
      OP_TABLE.each do |i, c|
        defination += "when #{i} then #{send_args(c)}\n"
      end
      defination += "else #{unknown_op} end"
    end

    defination = static_method_call

    class_eval("def run(op); #{defination} end")
  end
end
