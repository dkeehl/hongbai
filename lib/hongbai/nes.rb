require_relative 'sdl/sdl2'
require_relative './cpu'
require_relative './ppu'
require_relative './apu'
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
        video = SDL2::Video.new(win)
        map = KeyMap.default_1p
        controller = Controller.new(map)
        input = Input.new(controller)

        apu = Apu.new
        ppu = Ppu.new(rom, video)
        mem = Memory.new(apu, ppu, rom, input)
        cpu = Cpu.new(mem)
        nes = new(cpu, ppu, apu, mem, input)
        begin
          loop { nes.step }
        ensure
        end
      end
    end

    def initialize(cpu, ppu, apu, mem, input)
      @cpu = cpu
      @ppu = ppu
      @apu = apu
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
      @cpu.irq if scanline_irq || @apu.irq?
      if new_frame
        @input.poll
        @apu.flush
      end
    end
  end
end
