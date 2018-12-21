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
      Step.new(   1, 1, false, false, false, false, false),
      Step.new(   1, 2, false, false, false, false, false),
      Step.new(   1, 3, false, false, false, false, false),
      Step.new(7457, 4, false, false, false, true,  true ),
      Step.new(7456, 5, false, true,  true,  true,  true ),
      Step.new(7458, 6, false, false, false, true,  true ),
      Step.new(7457, 7, true,  false, false, false, false),
      Step.new(   1, 8, true,  true,  true,  true,  true ),
      Step.new(   1, 3, true,  false, false, false, false),
    ]
    MODE_1 = [
      Step.new(   1, 1, false, false, false, false, false),
      Step.new(   3, 2, false, true,  true,  true,  true ),
      Step.new(7456, 5, false, false, false, true,  true ),
      Step.new(7458, 4, false, true,  true,  true,  true ),
      Step.new(7458, 5, false, false, false, true,  true ),
      Step.new(7456, 6, false, true,  true,  true,  true ),
      Step.new(7458, 7, false, false, false, true,  true ),
      Step.new(7452, 3, false, false, false, false, false),
    ]

    SEQUENCERS = [MODE_0, MODE_1]

    def initialize(filter)
      # channels
      @pulse_1 = Pulse.new
      @pulse_2 = Pulse.new(true)

      @mixer = Mixer.new(@pulse_1, @pulse_2)
      @buffer = []
      @output = []
      @cycle = 0

      # Frame counter
      @sequencer = MODE_0
      @step = 0
      @cycles_until_next_step = @sequencer[@step].cycles
      # Because writings to 4017 have different effects upon different cpu cycles,
      # need these two buffers
      @val_4017 = nil
      @wrote_on_odd_cycle = nil

      # For resampling
      @filter = filter
      @sampling_counter = 0.0
      @decimation_counter = 0
    end

    def run
      # one step per cpu cycle
      # 1.789773MHz
      loop { step }
    end

    def step
      clock_channels
      clock_output
      clock_frame_counter
      @cycle += 1
    end

    def clock_channels
      # The triangle channel's timer is clocked every cpu cycle;
      # other channels' timers are clocked every second cpu cycle.
      if @cycle.odd?
        @pulse_1.clock
        @pulse_2.clock
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
        this_step = @sequence[@step]
        if this_step.clk_sweep_units
          @pulse_1.clock_sweep_unit
          @pulse_2.clock_sweep_unit
        end

        if this_step.clk_envelopes
          @pulse_1.clock_envelope
          @pulse_2.clock_envelope
        end

        if this_step.clk_length_counters
          @pulse_1.clock_length_counter
          @pulse_2.clock_length_counter
        end

        if this_step.clk_linear_counter
        end

        if this_step.clk_irq
        end

        @step = this_step.next_step
        @cycles_until_next_step = @sequence[@step].cycles
      end

      if @val_4017
        raise "No cpu cycle info after writing to $4017" if @wrote_on_odd_cycle.nil?
        @sequence = SEQUENCERS[@val_4017[7]]
        @step = @wrote_on_odd_cycle ? 0 : 1
        @cycles_until_next_step = @sequence[@step].cycles
        @val_4017 = @wrote_on_odd_cycle = nil
      end
    end
  end

  class Pulse
    MIN_PERIOD = 0x008
    MAX_PERIOD = 0x7ff
    WAVE_FORM = [0b0000_0001, 0b0000_0011, 0b0000_1111, 0b1111_1100].map do |n|
      (0..7).map {|i| n[7 - i] }
    end

    def initialize(pulse_2 = false)
      # Sweep unit
      @sweep_reload = false
      @sweep_enabled = false
      @sweep_negate = false
      @sweep_increase = -1 # A mask. -1 when sweep increases, 0 when sweep decreases.
      @sweep_period = 0
      @sweep_shift = 0
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

    def write_0(val)
      @envelope.write(val)
      @length_counter.halt = val[5] == 1
      @form = WAVE_FORM[(val >> 6) & 3]
    end

    def write_1(val)
      @sweep_reload = true
      @sweep_enabled = val[7] == 1
      @sweep_period = (val >> 4) & 7
      @sweep_negate = val[3] == 1
      @sweep_increase = @sweep_negate ? 0 : -1
      @sweep_shift = val & 7
    end

    def write_2(val)
      @wave_length = (@wave_length & 0x700) | (val & 0xff)
    end

    def write_3(val)
      @wave_length = (@wave_length & 0xff) | ((val & 0x7) << 8)
      @envelope.restart
      @length_counter.write(val)
      @step = 0
    end

    # When the period is not `valid`, the sweep unit will mute the channel.
    def valid_period?
      @wave_length >= MIN_PERIOD &&
      @wave_length + (@sweep_increase & (@wave_length >> @sweep_shift)) <= MAX_PERIOD
    end

    def audible?
      valid_period? && @envelope.output.nonzero? && @length_counter.count.nonzero?
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
      if @sweep_counter.zero? && @sweep_enabled && valid_period?
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

    attr_reader :count
    attr_writer :halt

    def write(val)
      @count = LENGTH_TABLE[val >> 3] if @enabled
    end

    def clock
      @count -= 1 unless @halt || @count.zero?
    end
  end

  class Mixer
    # Lookup tables
    PULSE_TABLE = (0..30).map {|n| n.zero? ? 0 : 95.52 / (8128.0 / n + 100) }
    TND_TABLE = (0..202).map {|n| n.zero? ? 0 : 163.67 / (24329.0 / n + 100) }

    def initialize(pulse_1, pulse_2)
      @pulse_1 = pulse_1
      @pulse_2 = pulse_2
    end

    def sample
      pulse_1 = @pulse_1.sample
      pulse_2 = @pulse_2.sample
      triangle = 0
      noise = 0
      dmc = 0

      pulse_out = PULSE_TABLE[pulse_1 + pulse_2]
      tnd_out = TND_TABLE[3 * triangle + 2 * noise + dmc]
      pulse_out + tnd_out
    end
  end
end
