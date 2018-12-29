require_relative 'sdl/sdl2'
require_relative './cpu'
require_relative './ppu'
require_relative './rom'
require_relative './mem'
require_relative './input'

module Hongbai
  class Nes
    def self.run(path)
      if rom = INes.from_file(path)
        SDL2.Init(SDL2::INIT_TIMER | SDL2::INIT_AUDIO | SDL2::INIT_VIDEO )

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

      vblank_nmi, scanline_irq, new_frame = @ppu.step(@mem.cycle)

      @cpu.nmi if vblank_nmi
      @cpu.irq if scanline_irq
      @input.poll if new_frame
    end

  end
end
