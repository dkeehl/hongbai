require_relative './sdl2'

module Hongbai
  module SDL2
    class AudioSpec < FFI::Struct
      layout(
        :freq,     :int,
        :format,   :uint16,
        :channels, :uint8,
        :silence,  :uint8,
        :samples,  :uint16,
        :padding,  :uint16,
        :size,     :uint32,
        :callback, :pointer,
        :userdata, :pointer,
      )
    end

    AUDIO_S8 = 0x8008
    AUDIO_S16LSB = 0x8010

    class Audio
      FORMAT = { 8 => AUDIO_S8, 16 => AUDIO_S16LSB }
      PACK = { 8 => "c*", 16 => "v*" }

      def initialize(sample_rate = 44100, bit_depth = 16)
        raise "Bit depth must be 8 or 16" unless bit_depth == 8 || bit_depth == 16
        @sample_rate = sample_rate
        @bit_depth = bit_depth
        @pack = PACK[@bit_depth]

        @delay = 1000 # in miliseconds
        @buf_limit = sample_rate * bit_depth / 8 * @delay / 1000

        desired = AudioSpec.new
        desired[:freq] = @sample_rate
        desired[:format] = FORMAT[@bit_depth]
        desired[:channels] = 1
        desired[:samples] = sample_rate / 60 * 2
        desired[:callback] = nil
        desired[:userdata] = nil

        obtained = AudioSpec.new
        @dev = SDL2.OpenAudioDevice(nil, 0, desired, obtained, 0)
        raise "Failed to open audio device" if @dev.zero?
        SDL2.PauseAudioDevice(@dev, 0)
      end

      def set_buf_limit(size)
        @buf_limit = size
        @delay = @buf_limit / @sample_rate / @bit_depth * 8 * 1000
      end

      def close
        SDL2.CloseAudioDevice(@dev)
      end

      def process(data)
        buf = data.pack(@pack)
        SDL2.QueueAudio(@dev, buf, buf.bytesize)
        #SDL2.ClearQueuedAudio(@dev) if SDL2.GetQueuedAudioSize(@dev) > @buf_limit
      end

      def play(data)
        if SDL2.GetQueuedAudioSize(@dev) > @buf_limit
          SDL2.Delay(@delay)
        end
        SDL2.QueueAudio(@dev, data, data.bytesize)
      end
    end
  end
end
