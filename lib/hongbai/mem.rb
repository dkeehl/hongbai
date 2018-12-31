module Hongbai
  class Memory
    def initialize(apu, ppu, rom, input)
      @apu = apu
      @ppu = ppu
      @rom = rom
      @input = input
      @ram = Array.new(0x800, 0)

      @read_map = Array.new(0x10000)
      @write_map = Array.new(0x10000)

      @oam_dma_triggered = nil

      @cycle = 0
      @trace = false

      init_memory_map
    end

    attr_accessor :trace
    attr_reader :cycle

    def reset
      @cycle = 0
      # FIXME: should also reset apu
    end

    def read(addr)
      do_dmc_dma(addr) if @apu.dmc.should_activate_dma?
      do_oam_dma(addr) if @oam_dma_triggered
      on_cpu_cycle
      @read_map[addr][addr]
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
        on_cpu_cycle
        @read_map[addr][addr]
      end

      def do_dmc_dma(addr)
        dma_read addr # halt
        dma_read addr # extra dmc dummy_read
        dma_read addr if @cycle.odd?
        val = dma_read(@apu.dmc.current_address)
        @apu.dmc.dma_write val
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
          if @apu.dmc.should_activate_dma?
            val = dma_read(@apu.dmc.current_address)
            @apu.dmc.dma_write val
            dma_read addr
          end
        end
      end

      def on_cpu_cycle
        @cycle += 1
        @apu.step
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
            when 0 then @ppu.method(:read_ppu_ctrl)
            when 1 then @ppu.method(:read_ppu_mask)
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
          add_mapping(i, @rom.prg_read_method, @rom.prg_write_method)
        end
      end
  end
end
