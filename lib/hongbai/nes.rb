require_relative 'sdl/sdl2'
require_relative 'sdl/video'
require_relative 'sdl/audio'
require_relative 'sdl/event'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'apu'
require_relative 'rom'
require_relative 'input'

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
        audio = SDL2::Audio.new(44100, 32, 1)
        map = KeyMap.default_1p
        controller = Controller.new(map)
        input = Input.new(controller)

        nes = new(rom, video, audio, input)
        nes.reset
        begin
          t = Time.now
          loop { nes.step }
        ensure
          dur = Time.now - t
          audio.close
          frames = nes.frame
          puts "#{frames} frames in %.1f seconds, %.1f FPS" % [dur, frames / dur]
        end
      end
    end

    def initialize(rom, video, audio, input)
      @input = input
      @rom = rom
      @rom.insert_to(self)
      @apu = Apu.new(audio, self)
      @dmc = @apu.dmc
      @ppu = Ppu.new(rom, video, self)
      @cpu = Cpu.new(self)
      @ram = Array.new(0x800, 0)

      @read_map = Array.new(0x10000)
      @write_map = Array.new(0x10000)

      @oam_dma_triggered = nil
      @active_dmc_dma = false

      @nmi = false
      @irq = false
      @apu_frame_irq = false
      @apu_dmc_irq = false
      @rom_irq = false

      # for debug
      @trace = false
      @frame = 0
      @cycle = 0

      init_memory_map
    end

    attr_reader :frame
    attr_writer :nmi, :active_dmc_dma

    def reset
      @cpu.reset
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

    def read(addr)
      do_dmc_dma(addr) if @active_dmc_dma
      do_oam_dma(addr) if @oam_dma_triggered
      ret = @read_map[addr][addr]
      on_cpu_cycle
      ret
    end

    def load(addr, val)
      on_cpu_cycle
      @write_map[addr][addr, val]
    end

    alias_method :fetch, :read
    alias_method :dummy_read, :read

    private
      def trigger_oam_dma(_addr, val)
        @oam_dma_triggered = val
      end

      def dma_read(addr)
        ret = @read_map[addr][addr]
        on_cpu_cycle
        ret
      end

      def do_dmc_dma(addr)
        dma_read addr # halt
        dma_read addr # extra dmc dummy_read
        dma_read addr if @cycle.odd?
        val = dma_read(@dmc.current_address)
        @dmc.dma_write val
      end

      def do_oam_dma(addr)
        start = @oam_dma_triggered << 8
        @oam_dma_triggered = nil
        dma_read addr # halt cycle
        dma_read addr if @cycle.odd? # align cycle
        256.times do |i|
          val = dma_read(start + i)
          on_cpu_cycle
          @ppu.write_oam_data(0x2004, val)
          if @active_dmc_dma
            val = dma_read(@dmc.current_address)
            @dmc.dma_write val
            dma_read addr
          end
        end
      end

      def on_cpu_cycle
        @cycle += 1
        @apu.step
        @ppu.main_loop.resume
        @ppu.main_loop.resume
        @ppu.main_loop.resume
      end

      def read_mirror_ram(addr)
        @ram[addr & 0x7ff]
      end

      def write_mirror_ram(addr, val)
        @ram[addr & 0x7ff] = val
      end

      def nop_read(addr)
        addr >> 8
      end

      def nop_write(_addr, _val); end

      def add_mapping(addr, read, write)
        @read_map[addr] = read
        @write_map[addr] = write
      end

      def init_memory_map
        # Memory map
        # $0000 - $07ff 2KB internal RAM
        (0..0x7ff).each do |i|
          add_mapping(i, @ram, @ram.method(:[]=))
        end
        # $0800 - $0fff
        # $1000 - $17ff
        # $1800 - $1fff 3 mirrors of $0000 - $07fff
        (0x800..0x1fff).each do |i|
          add_mapping(i, method(:read_mirror_ram), method(:write_mirror_ram))
        end
        # $2000 - $2007 PPU registers
        # $2008 - $3fff mirrors of $2000 - $2007
        (0x2000..0x3fff).each do |i|
          @read_map[i] =
            case i % 8
            when 2 then @ppu.method(:read_ppu_status)
            when 4 then @ppu.method(:read_oam_data)
            when 7 then @ppu.method(:read_ppu_data)
            else method(:nop_read)
            end
          @write_map[i] =
            case i % 8
            when 0 then @ppu.method(:write_ppu_ctrl)
            when 1 then @ppu.method(:write_ppu_mask)
            when 2 then method(:nop_write)
            when 3 then @ppu.method(:write_oam_addr)
            when 4 then @ppu.method(:write_oam_data)
            when 5 then @ppu.method(:write_ppu_scroll)
            when 6 then @ppu.method(:write_ppu_addr)
            when 7 then @ppu.method(:write_ppu_data)
            end
        end
        # $4000 - $4017 APU and IO registers
        # $4018 - $401f normally disabled APU and IO functionality
        (0x4000..0x4003).each do |i|
          add_mapping(
            i, method(:nop_read), @apu.pulse_1.method(:"write_#{i - 0x4000}"))
        end
        (0x4004..0x4007).each do |i|
          add_mapping(
            i, method(:nop_read), @apu.pulse_2.method(:"write_#{i - 0x4004}"))
        end
        [0x4008, 0x400a, 0x400b].each do |i|
          add_mapping(
            i, method(:nop_read), @apu.triangle.method(:"write_#{i - 0x4008}"))
        end
        [0x400c, 0x400e, 0x400f].each do |i|
          add_mapping(
            i, method(:nop_read), @apu.noise.method(:"write_#{i - 0x400c}"))
        end
        (0x4010..0x4013).each do |i|
          add_mapping(
            i, method(:nop_read), @apu.dmc.method(:"write_#{i - 0x4010}"))
        end

        add_mapping(0x4014, method(:nop_read), method(:trigger_oam_dma))
        add_mapping(0x4015, @apu.method(:read_4015), @apu.method(:write_4015))
        add_mapping(0x4016, @input.method(:read_4016), @input.method(:write_4016))
        add_mapping(0x4017, @input.method(:read_4017), @apu.method(:write_4017))

        ([0x4009, 0x400d] + (0x4018..0x401f).to_a).each do |i|
          add_mapping(i, method(:nop_read), method(:nop_write))
        end
        # $4020 - $ffff cartridge space
        (0x4020..0xffff).each do |i|
          add_mapping(i, @rom.prg_read_method(i), @rom.prg_write_method(i))
        end
      end
  end
end
