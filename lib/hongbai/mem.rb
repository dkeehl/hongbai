module Hongbai
  class Memory
    def initialize(ppu, rom, input)
      @ppu = ppu
      @rom = rom
      @input = input
      @ram = Array.new(0x800, 0)

      @dma_triggered = nil

      @cycle = 0
      @trace = false
    end

    attr_accessor :dma_triggered, :trace
    attr_reader :cycle

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
      on_cpu_cycle
      do_oma_dmc(addr) if @dma_triggered
      if addr < 0x2000
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
      on_cpu_cycle
      if addr < 0x2000
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

    def do_oma_dmc(addr)
      start = @dma_triggered << 8
      @dma_triggered = nil
      dummy_read addr
      dummy_read addr if @cycle.odd?
      256.times do |i|
        val = read(start + i)
        on_cpu_cycle
        @ppu.write_oam_data(val)
      end
    end

    alias_method :fetch, :read
    alias_method :dummy_read, :read

    def on_cpu_cycle
      @cycle += 1
    end
  end
end
