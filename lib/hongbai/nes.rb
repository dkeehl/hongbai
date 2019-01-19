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
      if rom = Rom.from_file(path)
        SDL2.Init(SDL2::INIT_TIMER | SDL2::INIT_AUDIO | SDL2::INIT_VIDEO )

        win = SDL2::Window.create("Hongbai",
                                  SDL2::Window::POS_CENTERED,
                                  SDL2::Window::POS_CENTERED,
                                  SCREEN_WIDTH, SCREEN_HEIGHT, 0)
        video = SDL2::Video.new(win)
        map = KeyMap.default_1p
        controller = Controller.new(map)
        input = Input.new(controller)

        nes = new(rom, video, input)
        begin
          t = Time.now
          loop { nes.step }
        ensure
          dur = Time.now - t
          frames = nes.frame
          puts "#{frames} frames in %.1f seconds, %.1f FPS" % [dur, frames / dur]
        end
      end
    end

    def initialize(rom, video, input)
      @input = input
      @apu = Apu.new
      rom.insert_to(self)
      @ppu = Ppu.new(rom, video, self)
      @mem = Memory.new(@apu, @ppu, rom, @input)
      @cpu = Cpu.new(@mem)

      @nmi = false
      @irq = false
      @apu_frame_irq = false
      @apu_dmc_irq = false
      @rom_irq = false

      # for debug
      @trace = false
      @frame = 0
    end

    def step
      if @nmi
        @nmi = false
        @cpu.nmi
      end

      @cpu.irq if @irq
      @cpu.step
    end

    def on_new_frame
      @input.poll
      @apu.flush
      @frame += 1
    end

    def update_irq_state
      @irq = @rom_irq || @apu_frame_irq || @apu_dmc_irq
    end

    def rom_irq=(b)
      @rom_irq = b
      update_irq_state
    end

    def apu_frame_irq=(b)
      @apu_frame_irq = b
      update_irq_state
    end

    def apu_dmc_irq=(b)
      @apu_dmc_irq = b
      update_irq_state
    end

    attr_reader :frame
    attr_writer :nmi
  end
end
