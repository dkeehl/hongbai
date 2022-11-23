require 'ffi'

module Hongbai
  module SDL2
    extend FFI::Library
    ffi_lib 'SDL2'

    class Version < FFI::Struct
      layout(
        :major, :uint8,
        :minor, :uint8,
        :patch, :uint8,
      )
    end

    # Check version
    attach_function(:GetVersion, :SDL_GetVersion, [:pointer], :void)
    ver = Version.new
    GetVersion(ver)
    ver = [ver[:major], ver[:minor], ver[:patch]]
    raise "Need SDL 2.0.4 or later" if (ver <=> [2, 0, 4]) < 0

    functions = {
      Init: [[:uint32], :int],
      Delay: [[:int], :void, blocking: true],
      Quit: [[], :void],

      # Video
      CreateWindow: [[:string, :int, :int, :int, :int, :uint32], :pointer],
      SetWindowIcon: [[:pointer, :pointer], :void],
      DestroyWindow: [[:pointer], :void],
      CreateRenderer: [[:pointer, :int, :uint32], :pointer],
      SetRenderDrawColor: [[:pointer, :uint8, :uint8, :uint8, :uint8], :int],
      RenderDrawPoint: [[:pointer, :int, :int], :int],
      RenderPresent: [[:pointer], :int],
      RenderClear: [[:pointer], :int],
      RenderCopy: [[:pointer, :pointer, :pointer, :pointer], :int],
      CreateTexture: [[:pointer, :uint32, :int, :int, :int], :pointer],
      UpdateTexture: [[:pointer, :pointer, :pointer, :int], :int],

      # Events
      PollEvent: [[:pointer], :int],

      # Audio
      OpenAudioDevice: [[:string, :int, :pointer, :pointer, :int], :uint32, blocking: true],
      PauseAudioDevice: [[:uint32, :int], :void, blocking: true],
      CloseAudioDevice: [[:uint32], :void, blocking: true],
      QueueAudio: [[:uint32, :pointer, :uint32], :int],
      GetQueuedAudioSize: [[:uint32], :uint32],
      ClearQueuedAudio: [[:uint32], :void],
    }

    functions.each do |name, params|
      attach_function(name, :"SDL_#{name}", *params)
    end

    INIT_TIMER = 0x00000001
    INIT_AUDIO = 0x00000010
    INIT_VIDEO = 0x00000020

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

    AUDIO_U8 = 0x0008
    AUDIO_S16LSB = 0x8010
  end
end
