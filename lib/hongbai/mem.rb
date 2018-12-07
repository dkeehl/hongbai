module Hongbai
  class Memory
    def initialize(ppu, rom)
      @ppu = ppu
      @rom = rom
      @ram = Array.new(0x800, 0)

      @dma_triggered = nil
    end

    attr_accessor :dma_triggered

    # Memory map
    # $0000 - $07ff 2KB internal RAM
    # $0800 - $0fff
    # $1000 - $17ff
    # $1800 - $1fff 3 mirrors of $0000 - $07fff
    # $2000 - $2007 PPU registers
    # $2008 - $3fff mirrors of $2000 - $2007
    # $4000 - $4017 APU and IO registers
    # $4018 - $401f normally disabled APU and IO functionality
    # $4020 - $ffff cartridge space
    def read(addr)
      if addr < 0x2000
        @ram[addr & 0x7ff]
      elsif addr < 0x4000
        @ppu.load(addr)
      elsif addr == 0x4014
        #https://forums.nesdev.com/viewtopic.php?f=3&t=14120
        0x40
      elsif addr == 0x4016
        0
        # TODO: "Unimplemented IO register"
      elsif addr < 0x4018
        0
        # TODO: "Unimplemented APU register"
      elsif addr < 0x4020
        0
      else
        @rom.prg_load(addr)
      end
    end

    def load(addr, val)
      if addr < 0x2000
        @ram[addr & 0x7ff] = val
      elsif addr < 0x4000
        @ppu.store(addr, val)
      elsif addr == 0x4014
        @dma_triggered = val
      elsif addr == 0x4016
        # TODO: "Unimplemented IO register"
        nil
      elsif addr < 0x4018
        nil
        # TODO: "Unimplemented APU register"
      elsif addr < 0x4020
        nil
      else
        @rom.prg_store(addr, val)
      end
    end

    def fetch(addr); read(addr) end
  end
end
