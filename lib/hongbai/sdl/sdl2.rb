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
      Quit: [[], :void],

      # Video
      CreateWindow: [[:string, :int, :int, :int, :int, :uint32], :pointer],
      SetWindowIcon: [[:pointer, :pointer], :void],
      DestroyWindow: [[:pointer], :void],
      CreateRenderer: [[:pointer, :int, :uint32], :pointer],
      SetRenderDrawColor: [[:pointer, :uint8, :uint8, :uint8, :uint8], :int],
      RenderDrawPoint: [[:pointer, :int, :int], :int],
      RenderPresent: [[:pointer], :int],

      # Events
      PollEvent: [[:pointer], :int],
    }

    functions.each do |name, params|
      attach_function(name, :"SDL_#{name}", *params)
    end

    INIT_TIMER = 0x00000001
    INIT_AUDIO = 0x00000010
    INIT_VIDEO = 0x00000020
  end
end
