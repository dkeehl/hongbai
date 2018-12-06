require_relative './cpu'
require_relative './ppu'
require_relative './rom'
require_relative './mem'

module Hongbai
  class Nes
    def self.run(path)
      if rom = INes.from_file(path)
        SDL2.init(SDL2::INIT_TIMER | SDL2::INIT_AUDIO |
                  SDL2::INIT_VIDEO | SDL2::INIT_EVENTS)

        win = SDL2::Window.create("hongbai",
                                  SDL2::Window::POS_CENTERED,
                                  SDL2::Window::POS_CENTERED,
                                  SCREEN_WIDTH, SCREEN_HEIGHT, 0)
        ppu = Ppu.new(rom, win)
        mem = Memory.new(ppu, rom)
        cpu = Cpu.new(mem)
        nes = new(cpu, ppu, mem)
        loop { nes.step }
      end
    end

    def initialize(cpu, ppu, mem)
      @cpu = cpu
      @ppu = ppu
      @mem = mem
    end

    def step
      @cpu.step

      if page = @mem.dma_triggered
        cycles = @cpu.counter.odd? ? 514 : 513
        @cpu.suspend(cycles)
        do_dma(page)
      end

      vblank_nmi, scanline_irq = @ppu.step(@cpu.counter)
      @cpu.nmi if vblank_nmi
      @cpu.irq if scanline_irq
    end

    def do_dma(page)
      start = page << 8
      256.times {|i| @ppu.write_oam(@mem.load(start + i)) }
      @mem.dma_triggered = nil
    end
  end
end
