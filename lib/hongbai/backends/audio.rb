require_relative '../sdl/sdl2'

module Hongbai
  module Backends
    module Audio
      OUTPUT_SAMPLE_RATE = 44.1 # kHz
      PACK = { 8 => "C*", 16 => "v*"}
    end
  end
end

module Hongbai::Backends::Audio
  class SaveToFile
    BUF_LIMIT = OUTPUT_SAMPLE_RATE * 1000 * 60

    def initialize(bit_depth = 8)
      @buffer = []
      @file = File.open("sound", "w")
      @pack = PACK[bit_depth]
    end

    def process(data)
      @buffer.concat(data)
      if @buffer.size > BUF_LIMIT
        buf = @buffer.pack(@pack)
        @buffer.clear
        @file.write(buf)
      end
    end

    def close
      flush
      @file.close
    end

    def flush
      if @buffer.size > 0
        buf = @buffer.pack(@pack)
        @buffer.clear
        @file.write(buf)
      end
    end

    def output_sample_rate
      OUTPUT_SAMPLE_RATE
    end
  end

  class SDL
    FORMAT = { 8 => Hongbai::SDL2::AUDIO_U8, 16 => Hongbai::SDL2::AUDIO_S16LSB }

    def initialize(bit_depth = 8, channels = 1, sample_rate = OUTPUT_SAMPLE_RATE * 1000)
      @sample_rate = sample_rate
      @bit_depth = bit_depth
      @channels = channels
      @pack = PACK[@bit_depth]

      @delay = 500 # in miliseconds
      # bit rate * seconds of delay * 2
      @buf_limit = sample_rate * channels * bit_depth / 8 * @delay / 1000 * 2

      desired = Hongbai::SDL2::AudioSpec.new
      desired[:freq] = @sample_rate
      desired[:format] = FORMAT[@bit_depth]
      desired[:channels] = @channels
      desired[:samples] = @bit_depth * @channels * 128
      desired[:callback] = nil
      desired[:userdata] = nil

      obtained = Hongbai::SDL2::AudioSpec.new
      @dev = Hongbai::SDL2.OpenAudioDevice(nil, 0, desired, obtained, 0)
      raise "Failed to open audio device" if @dev.zero?
      Hongbai::SDL2.PauseAudioDevice(@dev, 0)
    end

    def output_sample_rate
      @sample_rate
    end

    def set_buf_limit(size)
      @buf_limit = size
      @delay = @buf_limit / @channels / @sample_rate / @bit_depth * 8 * 1000 / 2
    end

    def close
      Hongbai::SDL2.CloseAudioDevice(@dev)
    end

    def process(data)
      buf = data.pack(@pack)
      Hongbai::SDL2.QueueAudio(@dev, buf, buf.bytesize)
    end

    # Functions for testing
    def play(data)
      while Hongbai::SDL2.GetQueuedAudioSize(@dev) > @buf_limit
        Hongbai::SDL2.Delay(@delay)
      end
      if Hongbai::SDL2.QueueAudio(@dev, data, data.bytesize).nonzero?
        close
        raise "SDL_QueueAudio failed"
      end
    end

    def flush
      # SDL keeps queuing some data repeatly. why?
      while Hongbai::SDL2.GetQueuedAudioSize(@dev) > 8000
        Hongbai::SDL2.Delay(@delay)
      end
    end
  end
end
