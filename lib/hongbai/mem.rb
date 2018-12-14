module Hongbai
  class Memory
    def initialize(ppu, rom, input)
      @ppu = ppu
      @rom = rom
      @input = input
      @ram = Array.new(0x800, 0)

      @dma_triggered = nil

      @trace = false
    end

    attr_accessor :dma_triggered, :trace

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
        #if @trace && (addr == 0x0086 || addr == 0x03ad)
        #  puts "read %04x" % addr
        #end
        @ram[addr & 0x7ff]
      elsif addr < 0x4000
        @ppu.load(addr)
      elsif addr == 0x4014
        # dma
        #https://forums.nesdev.com/viewtopic.php?f=3&t=14120
        0x40
      elsif addr == 0x4015
        # TODO APU
        0
      elsif addr == 0x4016
        0x40 ^ @input.read_4016
      elsif addr == 0x4017
        0x40 ^ @input.read_4017
      elsif addr < 0x4020
        0
      else
        @rom.prg_load(addr)
      end
    end

    def load(addr, val)
      if addr < 0x2000
        #if @trace && (addr == 0x0086 || addr == 0x03ad)
        #  puts "write to %04x val = %d" % [addr, val]
        #end
        @ram[addr & 0x7ff] = val
      elsif addr < 0x4000
        @ppu.store(addr, val)
      elsif addr == 0x4014
        @dma_triggered = val
      elsif addr == 0x4016
        @input.store(val)
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
