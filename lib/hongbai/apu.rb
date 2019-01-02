require_relative 'filter'

module Hongbai
  class Apu
    OUTPUT_SAMPLE_RATE = 44.1 # kHz
    NATIVE_SAMPLE_RATE = 1789.773 # kHz
    FILTER_MUL = 8 # A configuration of this emulator, not of the hardware
    INTERNAL_SAMPLE_RATE = OUTPUT_SAMPLE_RATE * FILTER_MUL
    SAMPLE_RATIO = NATIVE_SAMPLE_RATE / INTERNAL_SAMPLE_RATE

    # Frame counter sequencer modes
    Step = Struct.new(:cycles,             # Cpu cycles until next step
                      :next_step,          # Number of the next step, starts at 0
                      :clk_irq,
                      :clk_length_counters,
                      :clk_sweep_units,
                      :clk_linear_counter,
                      :clk_envelopes)
    MODE_0 = [
      Step.new(   1, 1, false, false, false, false, false), #0
      Step.new(   2, 2, false, false, false, false, false), #1
      Step.new(7457, 3, false, false, false, true,  true ), #2
      Step.new(7456, 4, false, true,  true,  true,  true ), #3
      Step.new(7458, 5, false, false, false, true,  true ), #4
      Step.new(7457, 6, true,  false, false, false, false), #5
      Step.new(   1, 7, true,  true,  true,  true,  true ), #6
      Step.new(   1, 2, true,  false, false, false, false), #7
    ]
    MODE_1 = [
      Step.new(   1, 1, false, false, false, false, false), #0
      Step.new(   1, 2, false, true,  true,  true,  true ), #1
      Step.new(7458, 3, false, false, false, true,  true ), #2
      Step.new(7456, 4, false, true,  true,  true,  true ), #3
      Step.new(7458, 5, false, false, false, true,  true ), #4
      Step.new(7456, 6, false, false, false, false, false), #5
      Step.new(7454, 2, false, true,  true,  true,  true ), #6
    ]

    SEQUENCERS = [MODE_0, MODE_1]

    def initialize
      # channels
      @pulse_1 = Pulse.new(self)
      @pulse_2 = Pulse.new(self, true)
      @triangle = Triangle.new
      @noise = Noise.new
      @dmc = Dmc.new

      @mixer = Mixer.new(@pulse_1, @pulse_2, @triangle, @noise, @dmc)
      @buffer = []
      @output = []
      @cycle = 0

      # Frame counter
      @sequencer = MODE_0
      @step = 0
      @cycles_until_next_step = @sequencer[@step].cycles
      @frame_interrupt = false
      @interrupt_inhibit = false
      # Because writings to 4017 have different effects upon different cpu cycles,
      # need this buffer
      @val_4017 = nil

      # For resampling
      @filter = Filter.new
      @sampling_counter = 0.0
      @decimation_counter = 0
    end

    attr_reader :pulse_1, :pulse_2, :triangle, :noise, :dmc, :frame_interrupt,
      :cycle

    def run
      # one step per cpu cycle
      # 1.789773MHz
      loop { step }
    end

    def step
      clock_channels
      clock_frame_counter
      clock_output
      @cycle += 1
    end

    def read_4015(_addr)
      p1 = @pulse_1 .length_counter.count > 0 ? 0b0000_0001 : 0
      p2 = @pulse_2 .length_counter.count > 0 ? 0b0000_0010 : 0
      t  = @triangle.length_counter.count > 0 ? 0b0000_0100 : 0
      n  = @noise   .length_counter.count > 0 ? 0b0000_1000 : 0
      d  = @dmc.bytes_remaining > 0 ? 0b0001_0000 : 0
      f  = @frame_interrupt        ? 0b0100_0000 : 0
      i  = @dmc.interrupt          ? 0b1000_0000 : 0

      # FIXME: if an frame interrupt flag was set at the same moment of the read,
      # it will read back as 1, but it will not be cleard
      @frame_interrupt = false

      p1 + p2 + t + n + d + f + i
    end

    def write_4015(_addr, val)
      @pulse_1 .length_counter.enable = val[0] == 1
      @pulse_2 .length_counter.enable = val[1] == 1
      @triangle.length_counter.enable = val[2] == 1
      @noise   .length_counter.enable = val[3] == 1
      @dmc     .enable = val[4] == 1

      @dmc.clear_interrupt
    end

    def write_4017(_addr, val)
      @interrupt_inhibit = val[6] == 1
      @frame_interrupt = false if @interrupt_inhibit 

      @sequencer = SEQUENCERS[val[7]]
      @step = @cycle.odd? ? 0 : 1
      @cycles_until_next_step = @sequencer[@step].cycles
    end

    def irq?
      @frame_interrupt || @dmc.interrupt
    end

    def flush
      @buffer.clear
    end

    def save_file
      #File.binwrite("sound", @buffer.pack("e*"))
    end

    private
      def clock_channels
        # The triangle channel's timer is clocked every cpu cycle.
        # Other channels' timers are clocked every second cpu cycle.
        @triangle.clock
        if @cycle.odd?
          @pulse_1.clock
          @pulse_2.clock
          @noise  .clock
          @dmc    .clock
        end
      end

      def clock_output
        @sampling_counter += 1.0
        return if @sampling_counter < SAMPLE_RATIO
        @sampling_counter -= SAMPLE_RATIO
        raw = @mixer.sample
        # Resample
        sample = @filter.apply(raw)
        @decimation_counter += 1
        if @decimation_counter >= FILTER_MUL
          @decimation_counter = 0
          @buffer << sample
        end
      end

      def clock_frame_counter
        @cycles_until_next_step -= 1
        if @cycles_until_next_step.zero?
          this_step = @sequencer[@step]

          if this_step.clk_sweep_units
            @pulse_1.clock_sweep_unit
            @pulse_2.clock_sweep_unit
          end

          if this_step.clk_envelopes
            @pulse_1.clock_envelope
            @pulse_2.clock_envelope
            @noise.clock_envelope
          end

          if this_step.clk_length_counters
            @pulse_1.clock_length_counter
            @pulse_2.clock_length_counter
            @triangle.clock_length_counter
            @noise.clock_length_counter
          end

          @triangle.clock_linear_counter if this_step.clk_linear_counter
          @frame_interrupt = true if this_step.clk_irq && !@interrupt_inhibit

          @step = this_step.next_step
          @cycles_until_next_step = @sequencer[@step].cycles
        end
      end
  end

  class Pulse
    MIN_PERIOD = 0x008
    MAX_PERIOD = 0x7ff
    WAVE_FORM = [0b0000_0001, 0b0000_0011, 0b0000_1111, 0b1111_1100].map do |n|
      (0..7).map {|i| n[7 - i] }
    end

    def initialize(apu, pulse_2 = false)
      @apu = apu
      # Sweep unit
      @sweep_reload = false
      @sweep_enabled = false
      @sweep_negate = false
      @sweep_increase = -1 # A mask. -1 when sweep increases, 0 when sweep decreases.
      @sweep_period = 0
      @sweep_shift = 0
      @sweep_counter = 0
      # doesn't change once initialized
      @complement = pulse_2 ? 0 : -1

      # Duty cycle
      @form = WAVE_FORM[0]
      @step = 0 # current step of wave form
      @wave_length = 0
      @timer = 0 # clocked every other cpu cycle

      @envelope = Envelope.new
      @length_counter = LengthCounter.new
    end

    attr_accessor :length_counter

    def write_0(_addr, val)
      @envelope.write(val)
      @length_counter.halt = val[5] == 1
      @form = WAVE_FORM[(val >> 6) & 3]
    end

    def write_1(_addr, val)
      @sweep_reload = true
      @sweep_enabled = val[7] == 1
      @sweep_period = (val >> 4) & 7
      @sweep_negate = val[3] == 1
      @sweep_increase = @sweep_negate ? 0 : -1
      @sweep_shift = val & 7
    end

    def write_2(_addr, val)
      @wave_length = (@wave_length & 0x700) | (val & 0xff)
    end

    def write_3(_addr, val)
      @wave_length = (@wave_length & 0xff) | ((val & 0x7) << 8)
      @length_counter.write val
      @envelope.restart
      @step = 0
    end

    # When the period is not `valid`, the sweep unit will mute the channel.
    def valid_period?
      @wave_length >= MIN_PERIOD &&
      @wave_length + (@sweep_increase & (@wave_length >> @sweep_shift)) <= MAX_PERIOD
    end

    def audible?
      valid_period? && @envelope.volume.nonzero? && @length_counter.count.nonzero?
    end

    def clock
      if @timer.zero?
        # update wave form generator
        @step.zero? ? @step = 7 : @step -= 1
        # reset timer
        @timer = @wave_length
      else
        @timer -= 1
      end
    end

    def clock_envelope
      @envelope.clock
    end

    def clock_sweep_unit
      if @sweep_enabled && @sweep_counter.zero? && valid_period? && @sweep_shift.nonzero?
        # adjust wave length
        if @sweep_negate
          @wave_length += @complement - (@wave_length >> @sweep_shift)
        else
          @wave_length += (@wave_length >> @sweep_shift)
        end
      end

      if @sweep_reload || @sweep_counter.zero?
        @sweep_reload = false
        @sweep_counter = @sweep_period
      else
        @sweep_counter -= 1
      end
    end

    def clock_length_counter
      @length_counter.clock
    end

    def sample
      audible? ? @form[@step] * @envelope.volume : 0
    end
  end

  class Envelope
    def initialize
      @counter = 0
      # @envelope_parameter is used as 1. the volume in constand volume,
      # and 2. the reload value for the counter
      @envelope_parameter = @decay_level = 0
      # flags
      @constant = false
      @loop = false
      @start = false
    end

    def write(val)
      @envelope_parameter = val & 0xf
      @constant = val[4] == 1
      @loop = val[5] == 1
    end

    def restart
      @start = true
    end

    def clock
      if @start
        @start = false
        @decay_level = 15
        @counter = @envelope_parameter
      else
        if @counter.zero?
          @counter = @envelope_parameter
          # clocks the decay level counter
          if @decay_level.zero?
            @decay_level = 15 if @loop
          else
            @decay_level -= 1
          end
        else
          @counter -= 1
        end
      end
    end

    def volume
      @constant ? @envelope_parameter : @decay_level
    end
  end

  class LengthCounter
    LENGTH_TABLE = [
      0x0a, 0xfe, 0x14, 0x02, 0x28, 0x04, 0x50, 0x06,
      0xa0, 0x08, 0x3c, 0x0a, 0x0e, 0x0c, 0x1a, 0x0e,
      0x0c, 0x10, 0x18, 0x12, 0x30, 0x14, 0x60, 0x16,
      0xc0, 0x18, 0x48, 0x1a, 0x10, 0x1c, 0x20, 0x1e,
    ]

    def initialize
      @enabled = false
      @count = 0
      @halt = false
    end

    attr_accessor :count, :halt

    def enable=(b)
      @enabled = b
      @count = 0 if !@enabled
    end

    def write(val)
      @count = LENGTH_TABLE[val >> 3] if @enabled
    end

    def clock
      @count -= 1 unless @halt || @count.zero?
    end
  end

  class Triangle
    SEQUENCE = [
      15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
      0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ]

    def initialize
      @period = 0 # In fact this is the period minus 1
      @timer = 0
      @step = 0
      
      # Linear counter
      @linear_counter = 0
      @linear_counter_reload = false
      @counter_reload_value = 0
      @control = false

      @length_counter = LengthCounter.new
    end

    attr_accessor :length_counter

    def write_0(_addr, val)
      @length_counter.halt = @control = val[7] == 1
      @counter_reload_value = val & 0x7f
    end

    def write_2(_addr, val)
      @period = (@period & 0x700) | val
    end

    def write_3(_addr, val)
      @period = (@period & 0xff) | ((val & 7) << 8)
      @length_counter.write val
      @linear_counter_reload = true
    end

    def clock
      if @timer.zero?
        @timer = @period
        if @linear_counter.nonzero? && @length_counter.count.nonzero?
          @step = (@step + 1) % 32
        end
      else
        @timer -= 1
      end
    end

    def clock_length_counter
      @length_counter.clock
    end

    def clock_linear_counter
      if @linear_counter_reload
        @linear_counter = @counter_reload_value
      elsif @linear_counter.nonzero?
        @linear_counter -= 1
      end
      @linear_counter_reload = false unless @control
    end

    def silenced?
      @linear_counter.zero? || @length_counter.count.zero? || @period < 2
    end

    def sample
      silenced? ? 0 : SEQUENCE[@step]
    end
  end

  class Noise
    PERIODS = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]
    
    def initialize
      @timer = 0
      @period = PERIODS[0]
      # Feedback shift register
      @shift = 1
      # Mode flag
      @mode = false
      @envelope = Envelope.new
      @length_counter = LengthCounter.new
    end

    attr_accessor :length_counter

    def write_0(_addr, val)
      @envelope.write val
      @length_counter.halt = val[5] == 1
    end

    def write_2(_addr, val)
      @mode = val[7] == 1
      @period = PERIODS[val & 0xf]
    end

    def write_3(_addr, val)
      @length_counter.write val
      @envelope.restart
    end

    def clock
      if @timer.zero?
        @timer = @period
        # clock shift register
        feedback = @shift[0] ^ @shift[@mode ? 6 : 1]
        @shift = (@shift >> 1) | (feedback << 14)
      else
        @timer -= 1
      end
    end

    def clock_envelope
      @envelope.clock
    end

    def clock_length_counter
      @length_counter.clock
    end

    def silenced?
      @shift[0] == 1 || @length_counter.count.zero?
    end

    def sample
      silenced? ? 0 : @envelope.volume
    end
  end

  class Dmc
    RATE_TABLE = [
      428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54
    ].map {|n| n / 2 } # devide cpu cycles by 2 to get apu cycle counts

    def initialize
      @enabled = false

      @rate = RATE_TABLE[0]
      @timer = @rate

      @output = 0

      # memory reader
      @enable_interrupt = false
      @interrupt = false
      @loop = false
      @sample_address = 0xc000
      @current_address = @sample_address
      @sample_length = 0
      @bytes_remaining = @sample_length

      @sample_buffer = nil

      # output unit
      @shift = 0
      @bits_remaining = 8
      @silence = true
    end

    attr_reader :interrupt, :bytes_remaining, :current_address

    def enable=(b)
      @enabled = b
      if !@enabled
        @bytes_remaining = 0
      elsif @bytes_remaining.zero?
        @current_address = @sample_address
        @bytes_remaining = @sample_length
      end
    end

    def write_0(_addr, val)
      @enable_interrupt = val[7] == 1
      @interrupt = false if !@enable_interrupt
      @loop = val[6] == 1
      @rate = RATE_TABLE[val & 0xf]
    end

    def write_1(_addr, val)
      @output = val & 0x7f
    end

    def write_2(_addr, val)
      @sample_address = 0xc000 + val * 64
    end

    def write_3(_addr, val)
      @sample_length = val * 16 + 1
    end

    def clear_interrupt
      @interrupt = false
    end

    def clock
      if @timer.zero?
        @timer = @rate
        update_output unless @silence
        @shift >> 1
        @bits_remaining -= 1
        new_cycle if @bits_remaining.zero?
      else
        @timer -= 1
      end
    end

    def sample
      @output
    end

    def should_activate_dma?
      @sample_buffer.nil? && @bytes_remaining.nonzero?
    end

    def dma_write(val)
      @sample_buffer = val
      @current_address += 1
      @current_address -= 0x8000 if @current_address > 0xffff
      @bytes_remaining -= 1
      if @bytes_remaining.zero?
        if @loop
          @current_address = @sample_address
          @bytes_remaining = @sample_length
        else
          @interrupt = true if @enable_interrupt
        end
      end
    end

    private
      def update_output
        if @shift[0].zero?
          @output -= 2 unless @output < 2
        else
          @output += 2 unless @output > 125
        end
      end

      def new_cycle
        @bits_remaining = 8
        if @sample_buffer.nil?
          @silence = true
        else
          @silence = false
          @shift = @sample_buffer
          @sample_buffer = nil
        end
      end
  end

  class Mixer
    PULSE_TABLE = (0..30).map {|n| n.zero? ? 0 : 95.52 / (8128.0 / n + 100) }
    TND_TABLE = (0..202).map {|n| n.zero? ? 0 : 163.67 / (24329.0 / n + 100) }

    def initialize(pulse_1, pulse_2, triangle, noise, dmc)
      @pulse_1 = pulse_1
      @pulse_2 = pulse_2
      @triangle = triangle
      @noise = noise
      @dmc = dmc
    end

    def sample
      pulse_1 = @pulse_1.sample
      pulse_2 = @pulse_2.sample
      triangle = @triangle.sample
      noise = @noise.sample
      dmc = @dmc.sample

      pulse_out = PULSE_TABLE[pulse_1 + pulse_2]
      tnd_out = TND_TABLE[3 * triangle + 2 * noise + dmc]
      pulse_out + tnd_out
    end
  end
end
