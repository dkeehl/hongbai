require 'assembler'

describe Assembler do
  before do
    @a = Assembler.new
  end

  it 'assembles absolute mode instructinons correctly' do
    expect(@a.eval "ADC $123a").to eql([0x6d, 58, 18])
    expect(@a.eval "AND $123a").to eql([0x2d, 58, 18])
    expect(@a.eval "ASL $123a").to eql([0x0e, 58, 18])
    expect(@a.eval "BIT $123a").to eql([0x2c, 58, 18])
    expect(@a.eval "CMP $123a").to eql([0xcd, 58, 18])
    expect(@a.eval "CPX $123a").to eql([0xec, 58, 18])
    expect(@a.eval "CPY $123a").to eql([0xcc, 58, 18])
    expect(@a.eval "DEC $123a").to eql([0xce, 58, 18])
    expect(@a.eval "EOR $123a").to eql([0x4d, 58, 18])
    expect(@a.eval "INC $123a").to eql([0xee, 58, 18])
    expect(@a.eval "JMP $123a").to eql([0x4c, 58, 18])
    expect(@a.eval "JSR $123a").to eql([0x20, 58, 18])
    expect(@a.eval "LDA $123a").to eql([0xad, 58, 18])
    expect(@a.eval "LDX $123a").to eql([0xae, 58, 18])
    expect(@a.eval "LDY $123a").to eql([0xac, 58, 18])
    expect(@a.eval "LSR $123a").to eql([0x4e, 58, 18])
    expect(@a.eval "ORA $123a").to eql([0x0d, 58, 18])
    expect(@a.eval "ROL $123a").to eql([0x2e, 58, 18])
    expect(@a.eval "SBC $123a").to eql([0xed, 58, 18])
    expect(@a.eval "STA $123a").to eql([0x8d, 58, 18])
    expect(@a.eval "STX $123a").to eql([0x8e, 58, 18])
    expect(@a.eval "STY $123a").to eql([0x8c, 58, 18])
  end

  it 'assembles absolute x mode instructinons correctly' do
    expect(@a.eval "ADC $123a,X").to eql([0x7d, 58, 18])
    expect(@a.eval "AND $123a,X").to eql([0x3d, 58, 18])
    expect(@a.eval "ASL $123a,X").to eql([0x1e, 58, 18])
    expect(@a.eval "CMP $123a,X").to eql([0xdd, 58, 18])
    expect(@a.eval "DEC $123a,X").to eql([0xde, 58, 18])
    expect(@a.eval "EOR $123a,X").to eql([0x5d, 58, 18])
    expect(@a.eval "INC $123a,X").to eql([0xfe, 58, 18])
    expect(@a.eval "LDA $123a,X").to eql([0xbd, 58, 18])
    expect(@a.eval "LDY $123a,X").to eql([0xbc, 58, 18])
    expect(@a.eval "LSR $123a,X").to eql([0x5e, 58, 18])
    expect(@a.eval "ORA $123a,X").to eql([0x1d, 58, 18])
    expect(@a.eval "ROL $123a,X").to eql([0x7e, 58, 18])
    expect(@a.eval "SBC $123a,X").to eql([0xfd, 58, 18])
    expect(@a.eval "STA $123a,X").to eql([0x9d, 58, 18])
  end

  it 'assembles absolute y mode instructinons correctly' do
    expect(@a.eval "ADC $123a,Y").to eql([0x79, 58, 18])
    expect(@a.eval "AND $123a,Y").to eql([0x39, 58, 18])
    expect(@a.eval "CMP $123a,Y").to eql([0xd9, 58, 18])
    expect(@a.eval "EOR $123a,Y").to eql([0x59, 58, 18])
    expect(@a.eval "LDA $123a,Y").to eql([0xb9, 58, 18])
    expect(@a.eval "LDX $123a,Y").to eql([0xbe, 58, 18])
    expect(@a.eval "ORA $123a,Y").to eql([0x19, 58, 18])
    expect(@a.eval "SBC $123a,Y").to eql([0xf9, 58, 18])
    expect(@a.eval "STA $123a,Y").to eql([0x99, 58, 18])
  end

  it 'assembles accumulator mode instructinons correctly' do
    expect(@a.eval "ASL").to eql([0x0a])
    expect(@a.eval "LSR").to eql([0x4a])
    expect(@a.eval "ROL").to eql([0x2a])
  end

  it 'assembles immediate mode instructinons correctly' do
    expect(@a.eval "ADC #4").to eql([0x69, 4])
    expect(@a.eval "AND #4").to eql([0x29, 4])
    expect(@a.eval "CMP #4").to eql([0xc9, 4])
    expect(@a.eval "CPX #4").to eql([0xe0, 4])
    expect(@a.eval "CPY #4").to eql([0xc0, 4])
    expect(@a.eval "EOR #4").to eql([0x49, 4])
    expect(@a.eval "LDA #4").to eql([0xa9, 4])
    expect(@a.eval "LDX #4").to eql([0xa2, 4])
    expect(@a.eval "LDY #4").to eql([0xa0, 4])
    expect(@a.eval "ORA #4").to eql([0x09, 4])
    expect(@a.eval "SBC #4").to eql([0xe9, 4])
  end

  it 'assembles implied mode instructinons correctly' do
    expect(@a.eval "BRK").to eql([0x00])
    expect(@a.eval "CLC").to eql([0x18])
    expect(@a.eval "CLD").to eql([0xd8])
    expect(@a.eval "CLI").to eql([0x58])
    expect(@a.eval "CLV").to eql([0x88])
    expect(@a.eval "DEX").to eql([0xca])
    expect(@a.eval "DEY").to eql([0x88])
    expect(@a.eval "INX").to eql([0xe8])
    expect(@a.eval "INY").to eql([0xc8])
    expect(@a.eval "NOP").to eql([0xea])
    expect(@a.eval "PHA").to eql([0x48])
    expect(@a.eval "PHP").to eql([0x08])
    expect(@a.eval "PLA").to eql([0x68])
    expect(@a.eval "PLP").to eql([0x28])
    expect(@a.eval "RTI").to eql([0x40])
    expect(@a.eval "RTS").to eql([0x60])
    expect(@a.eval "SEC").to eql([0x38])
    expect(@a.eval "SED").to eql([0xf8])
    expect(@a.eval "SEI").to eql([0x78])
    expect(@a.eval "TAX").to eql([0xaa])
    expect(@a.eval "TAY").to eql([0xa8])
    expect(@a.eval "TSX").to eql([0xba])
    expect(@a.eval "TSA").to eql([0x8a])
    expect(@a.eval "TXS").to eql([0x9a])
    expect(@a.eval "TYA").to eql([0x98])
  end

  it 'assembles indirect mode instructinons correctly' do
    expect(@a.eval "JMP ($123a)").to eql([0x6c, 58, 18])
  end

  it 'assembles indirect x mode instructinons correctly' do
    expect(@a.eval "ADC ($4,X)").to eql([0x61, 4])
    expect(@a.eval "AND ($4,X)").to eql([0x21, 4])
    expect(@a.eval "CMP ($4,X)").to eql([0xc1, 4])
    expect(@a.eval "EOR ($4,X)").to eql([0x41, 4])
    expect(@a.eval "LDA ($4,X)").to eql([0xa1, 4])
    expect(@a.eval "ORA ($4,X)").to eql([0x01, 4])
    expect(@a.eval "SBC ($4,X)").to eql([0xe1, 4])
    expect(@a.eval "STA ($4,X)").to eql([0x81, 4])
  end

  it 'assembles indirect y mode instructinons correctly' do
    expect(@a.eval "ADC ($4),Y").to eql([0x71, 4])
    expect(@a.eval "AND ($4),Y").to eql([0x31, 4])
    expect(@a.eval "CMP ($4),Y").to eql([0xd1, 4])
    expect(@a.eval "EOR ($4),Y").to eql([0x51, 4])
    expect(@a.eval "LDA ($4),Y").to eql([0xb1, 4])
    expect(@a.eval "ORA ($4),Y").to eql([0x11, 4])
    expect(@a.eval "SBC ($4),Y").to eql([0xf1, 4])
    expect(@a.eval "STA ($4),Y").to eql([0x91, 4])
  end

  it 'assembles relative mode instructinons correctly' do
    expect(@a.eval "BCC $4").to eql([0x90, 4])
    expect(@a.eval "BCS $4").to eql([0xb0, 4])
    expect(@a.eval "BEQ $4").to eql([0xf0, 4])
    expect(@a.eval "BMI $4").to eql([0x30, 4])
    expect(@a.eval "BNE $4").to eql([0xd0, 4])
    expect(@a.eval "BPL $4").to eql([0x10, 4])
    expect(@a.eval "BVC $4").to eql([0x50, 4])
    expect(@a.eval "BVS $4").to eql([0x70, 4])
  end

  it 'assembles zero page mode instructinons correctly' do
    expect(@a.eval "ADC $4").to eql([0x65, 4])
    expect(@a.eval "AND $4").to eql([0x25, 4])
    expect(@a.eval "ASL $4").to eql([0x06, 4])
    expect(@a.eval "BIT $4").to eql([0x24, 4])
    expect(@a.eval "CMP $4").to eql([0xc5, 4])
    expect(@a.eval "CPX $4").to eql([0xe4, 4])
    expect(@a.eval "CPY $4").to eql([0xc4, 4])
    expect(@a.eval "DEC $4").to eql([0xc6, 4])
    expect(@a.eval "EOR $4").to eql([0x45, 4])
    expect(@a.eval "INC $4").to eql([0xe6, 4])
    expect(@a.eval "LDA $4").to eql([0xa5, 4])
    expect(@a.eval "LDX $4").to eql([0xa6, 4])
    expect(@a.eval "LDY $4").to eql([0xa4, 4])
    expect(@a.eval "LSR $4").to eql([0x46, 4])
    expect(@a.eval "ORA $4").to eql([0x05, 4])
    expect(@a.eval "ROL $4").to eql([0x26, 4])
    expect(@a.eval "SBC $4").to eql([0xe5, 4])
    expect(@a.eval "STA $4").to eql([0x85, 4])
    expect(@a.eval "STX $4").to eql([0x86, 4])
    expect(@a.eval "STY $4").to eql([0x84, 4])
  end

  it 'assembles zero page x mode instructinons correctly' do
    expect(@a.eval "ADC $4,X").to eql([0x75, 4])
    expect(@a.eval "AND $4,X").to eql([0x35, 4])
    expect(@a.eval "ASL $4,X").to eql([0x16, 4])
    expect(@a.eval "CMP $4,X").to eql([0xd5, 4])
    expect(@a.eval "DEC $4,X").to eql([0xd6, 4])
    expect(@a.eval "EOR $4,X").to eql([0x55, 4])
    expect(@a.eval "INC $4,X").to eql([0xf6, 4])
    expect(@a.eval "LDA $4,X").to eql([0xb5, 4])
    expect(@a.eval "LDY $4,X").to eql([0xb4, 4])
    expect(@a.eval "LSR $4,X").to eql([0x56, 4])
    expect(@a.eval "ORA $4,X").to eql([0x15, 4])
    expect(@a.eval "ROL $4,X").to eql([0x36, 4])
    expect(@a.eval "SBC $4,X").to eql([0xf5, 4])
    expect(@a.eval "STA $4,X").to eql([0x95, 4])
    expect(@a.eval "STY $4,X").to eql([0x94, 4])
  end

  it 'assembles zero page y mode instructinons correctly' do
    expect(@a.eval "LDX $4,Y").to eql([0xb6, 4])
    expect(@a.eval "STX $4,Y").to eql([0x96, 4])
  end

  it 'assembles multiple lines correctly' do
    expect(@a.eval "LDX $4,Y\nADC $4,X\nSTY $4\n").to eql([0xb6, 4, 0x75, 4, 0x84, 4])
  end
end