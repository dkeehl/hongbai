require './cpu'
require './ppu'
require './rom'
require './mem'

module Hongbai
  class Nes
    def self.run(path)
      if rom = INes.from_file(path)
        SDL2.init(SDL2::INIT_TIMER | SDL2::INIT_AUDIO |
                  SDL2::INIT_VIDEO | SDL2::INIT_EVENTS)

        win = SDL2::Window.create("Hongbai",
                                  SDL2::Window::POS_CENTERED,
                                  SDL2::Window::POS_CENTERED,
                                  SCREEN_WIDTH, SCREEN_HEIGHT, 0)
        ppu = Ppu.new(rom, win)
        mem = Memory.new(ppu, rom)
        cpu = Cpu.new(mem)
        nes = new(cpu, ppu, mem)
        #begin
          loop { nes.step }
        #rescue StandardError => e
          #puts e
          #puts nes.count
        #end
      end
    end

    def initialize(cpu, ppu, mem)
      @cpu = cpu
      @ppu = ppu
      @mem = mem
      @trace = false
      @count = 0
    end

    attr_reader :count

    def step
      #@frame = @ppu.frame
      #if @frame == 33 && @ppu.scanline == 46
      #  @trace = true
      #  @cpu.trace = true
      #  @mem.trace = true
      #elsif @frame == 34 
      #  @trace = false
      #  @cpu.trace = false
      #  @mem.trace = false
      #end

      #if @trace
      #  print "frame #{@frame} scanline #{@ppu.scanline} step #{@count}: "
      #end
      @cpu.step

      #if @trace
      #  @count += 1
      #end

      if page = @mem.dma_triggered
        #if @trace
        #  puts "oma at step #{@count}"
        #end
        cycles = @cpu.cycle.odd? ? 514 : 513
        @cpu.suspend(cycles)
        do_dma(page)
      end

      vblank_nmi, scanline_irq = @ppu.step(@cpu.cycle)

      @cpu.nmi if vblank_nmi
      @cpu.irq if scanline_irq
    end

    def do_dma(page)
      start = page << 8
      256.times do |i|
        val = @mem.read(start + i) 
        @ppu.write_oam_data(val)
      end
      @mem.dma_triggered = nil
    end
  end
end
