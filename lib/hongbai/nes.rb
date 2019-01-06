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
          t = Time.now
          loop { nes.step }
        ensure
          dur = Time.now - t
          frames = ppu.frame
          puts "#{frames} frames in %.1f seconds, %.1f FPS" % [dur, frames / dur]
        end
      end
    end

    CYCLES_PER_SCANLINE = 114 
    def initialize(cpu, ppu, apu, mem, input)
      @cpu = cpu
      @ppu = ppu.main_loop
      @apu = apu
      @mem = mem
      @input = input
      @next_scanline_cycle = CYCLES_PER_SCANLINE

      # for debug
      @trace = false
      @count = 0
    end

    # FIXME: IRQ timing
    def step
      @cpu.step
      @cpu.irq if @apu.irq?
      cycle = @mem.cycle
      while @next_scanline_cycle < cycle
        vblank_nmi, scanline_irq, new_frame = @ppu.resume
        @cpu.nmi if vblank_nmi
        @cpu.irq if scanline_irq
        if new_frame
          @input.poll
          @apu.flush
        end
        @next_scanline_cycle += CYCLES_PER_SCANLINE
      end
    end

  end
end
