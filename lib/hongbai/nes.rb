require_relative './cpu'
require_relative './ppu'
require_relative './rom'
require_relative './mem'
require_relative './input'

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
        map = KeyMap.default_1p
        controller = Controller.new(map)
        input = Input.new(controller)

        ppu = Ppu.new(rom, win)
        mem = Memory.new(ppu, rom, input)
        cpu = Cpu.new(mem)
        nes = new(cpu, ppu, mem, input)
        loop { nes.step }
      end
    end

    def initialize(cpu, ppu, mem, input)
      @cpu = cpu
      @ppu = ppu
      @mem = mem
      @input = input

      # for debug
      @trace = false
      @count = 0
    end

    def step
      @cpu.step

      if page = @mem.dma_triggered
        cycles = @cpu.cycle.odd? ? 514 : 513
        @cpu.suspend(cycles)
        do_dma(page)
      end

      vblank_nmi, scanline_irq, new_frame = @ppu.step(@cpu.cycle)

      @cpu.nmi if vblank_nmi
      @cpu.irq if scanline_irq
      @input.poll if new_frame
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
