#####################################################################
#A very simple 6502 assembler for testing the CPU emulator
#
#
#

class Assembler
  def initialize
    @codemap = {
      'ADC_IM' => 0x69,
      'ADC_ZP' => 0x65,
      'ADC_ZX' => 0x75,
      'ADC_AB' => 0x6d,
      'ADC_AX' => 0x7d,
      'ADC_AY' => 0x79,
      'ADC_IX' => 0x61,
      'ADC_IY' => 0x71,
      'AND_IM' => 0x29,
      'AND_ZP' => 0x25,
      'AND_ZX' => 0x35,
      'AND_AB' => 0x2d,
      'AND_AX' => 0x3d,
      'AND_AY' => 0x39,
      'AND_IX' => 0x21,
      'AND_IY' => 0x31,
      'ASL_NO' => 0x0a,
      'ASL_ZP' => 0x06,
      'ASL_ZX' => 0x16,
      'ASL_AB' => 0x0e,
      'ASL_AX' => 0x1e,
      'BIT_ZP' => 0x24,
      'BIT_AB' => 0x2c,
      'BRK_NO' => 0x00,
      'CLC_NO' => 0x18,
      'CLD_NO' => 0xd8,
      'CLI_NO' => 0x58,
      'CLV_NO' => 0xb8,
      'CMP_IM' => 0xc9,
      'CMP_ZP' => 0xc5,
      'CMP_ZX' => 0xd5,
      'CMP_AB' => 0xcd,
      'CMP_AX' => 0xdd,
      'CMP_AY' => 0xd9,
      'CMP_IX' => 0xc1,
      'CMP_IY' => 0xd1,
      'CPX_IM' => 0xe0,
      'CPX_ZP' => 0xe4,
      'CPX_AB' => 0xec,
      'CPY_IM' => 0xc0,
      'CPY_ZP' => 0xc4,
      'CPY_AB' => 0xcc,
      'DEC_ZP' => 0xc6,
      'DEC_ZX' => 0xd6,
      'DEC_AB' => 0xce,
      'DEC_AX' => 0xde,
      'DEX_NO' => 0xca,
      'DEY_NO' => 0x88,
      'EOR_IM' => 0x49,
      'EOR_ZP' => 0x45,
      'EOR_ZX' => 0x55,
      'EOR_AB' => 0x4d,
      'EOR_AX' => 0x5d,
      'EOR_AY' => 0x59,
      'EOR_IX' => 0x41,
      'EOR_IY' => 0x51,
      'INC_ZP' => 0xe6,
      'INC_ZX' => 0xf6,
      'INC_AB' => 0xee,
      'INC_AX' => 0xfe,
      'INX_NO' => 0xe8,
      'INY_NO' => 0xc8,
      'JMP_AB' => 0x4c,
      'JSR_AB' => 0x20,
      'LDA_IM' => 0xa9,
      'LDA_ZP' => 0xa5,
      'LDA_ZX' => 0xb5,
      'LDA_AB' => 0xad,
      'LDA_AX' => 0xbd,
      'LDA_AY' => 0xb9,
      'LDA_IX' => 0xa1,
      'LDA_IY' => 0xb1,
      'LDX_IM' => 0xa2,
      'LDX_ZP' => 0xa6,
      'LDX_ZY' => 0xb6,
      'LDX_AB' => 0xae,
      'LDX_AY' => 0xbe,
      'LDY_IM' => 0xa0,
      'LDY_ZP' => 0xa4,
      'LDY_ZX' => 0xb4,
      'LDY_AB' => 0xac,
      'LDY_AX' => 0xbc,
      'LSR_NO' => 0x4a,
      'LSR_ZP' => 0x46,
      'LSR_ZX' => 0x56,
      'LSR_AB' => 0x4e,
      'LSR_AX' => 0x5e,
      'NOP_NO' => 0xea,
      'ORA_IM' => 0x09,
      'ORA_ZP' => 0x05,
      'ORA_ZX' => 0x15,
      'ORA_AB' => 0x0d,
      'ORA_AX' => 0x1d,
      'ORA_AY' => 0x19,
      'ORA_IX' => 0x01,
      'ORA_IY' => 0x11,
      'PHA_NO' => 0x48,
      'PHP_NO' => 0x08,
      'PLA_NO' => 0x68,
      'PLP_NO' => 0x28,
      'ROL_NO' => 0x2a,
      'ROL_ZP' => 0x26,
      'ROL_ZX' => 0x36,
      'ROL_AB' => 0x2e,
      'ROL_AX' => 0x3e,
      'ROR_NO' => 0x6a,
      'ROR_ZP' => 0x66,
      'ROR_ZX' => 0x76,
      'ROR_AB' => 0x6e,
      'ROR_AX' => 0x7e,
      'RTI_NO' => 0x40,
      'RTS_NO' => 0x60,
      'SBC_IM' => 0xe9,
      'SBC_ZP' => 0xe5,
      'SBC_ZX' => 0xf5,
      'SBC_AB' => 0xed,
      'SBC_AX' => 0xfd,
      'SBC_AY' => 0xf9,
      'SBC_IX' => 0xe1,
      'SBC_IY' => 0xf1,
      'SEC_NO' => 0x38,
      'SED_NO' => 0xf8,
      'SEI_NO' => 0x78,
      'STA_ZP' => 0x85,
      'STA_ZX' => 0x95,
      'STA_AB' => 0x8d,
      'STA_AX' => 0x9d,
      'STA_AY' => 0x99,
      'STA_IX' => 0x81,
      'STA_IY' => 0x91,
      'STX_ZP' => 0x86,
      'STX_ZY' => 0x96,
      'STX_AB' => 0x8e,
      'STY_ZP' => 0x84,
      'STY_ZX' => 0x94,
      'STY_AB' => 0x8c,
      'TAX_NO' => 0xaa,
      'TAY_NO' => 0xa8,
      'TSX_NO' => 0xba,
      'TXA_NO' => 0x8a,
      'TXS_NO' => 0x9a,
      'TYA_NO' => 0x98,
      'BCC_ZP' => 0x90,
      'BCS_ZP' => 0xb0,
      'BEQ_ZP' => 0xf0,
      'BMI_ZP' => 0x30,
      'BNE_ZP' => 0xd0,
      'BPL_ZP' => 0x10,
      'BVC_ZP' => 0x50,
      'BVS_ZP' => 0x70,
      'JMP_IN' => 0x6c,
    }
  end

  def eval_proc(exp, array)
    commands = exp.upcase.split("\n")
    target = array

    commands.each do |cmd|
      opcode = get_opcode(cmd)
      operator = get_operator(cmd)

      if opcode
        target = target.push(opcode) + operator
      end
    end

    return target
  end

  def get_opcode(cmd)
    mode  = detect_mode(cmd)
    instrc_name = cmd[/\b[A-Z]{3}\b/]
    instruction = "#{instrc_name}_#{mode}"

    opcode = @codemap[instruction]
  end

  def get_operator(cmd)
    n = cmd[/#([0-9]+)/, 1]
    m = cmd[/\$([0-9A-F]+)/, 1]
    if n
      [n.to_i]
    elsif m
      i = m.to_i(16)
      if i < 256
        [i]
      else
        [i & 0xff, i >> 8]
      end
    else
      []
    end      
  end

  def detect_mode(cmd)
    has_a_sharp = cmd.include?('#')
    has_a_x = cmd[/,\s*X\s*[^\)]?/]
    has_a_y = cmd[/[^\)],\s*Y/]
    indirect_x = cmd[/,\s*X\s*\)/]
    indirect_y = cmd[/\),\s*Y/]
    number_of_operators = get_operator(cmd).size
    #JMP indirect
    jmp_indirect = cmd[/JMP\s*\(/]


    if has_a_sharp
      'IM'
    elsif jmp_indirect
      'IN'        
    elsif number_of_operators == 1
      if indirect_x
        'IX'
      elsif indirect_y
        'IY'
      elsif has_a_x
        'ZX'
      elsif has_a_y
        'ZY'
      else
        'ZP'
      end
    elsif number_of_operators == 2
      if has_a_x
        'AX'
      elsif has_a_y
        'AY'
      else
        'AB'
      end
    else
      'NO'
    end
  end

  def eval(exp)
    eval_proc(exp, [])
  end
end