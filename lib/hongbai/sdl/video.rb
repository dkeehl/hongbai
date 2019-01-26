require_relative 'sdl2'

module Hongbai
  module SDL2
    class Window
      POS_CENTERED = 0x2FFF0000
      def self.create(title, x, y, w, h, flags)
        win_ptr = SDL2.CreateWindow(title, x, y, w, h, flags)
        new(win_ptr)
      end

      def initialize(win_ptr)
        @win_ptr = win_ptr
      end

      def as_ptr
        @win_ptr
      end

      def destroy
        SDL2.DestroyWindow(@win_ptr)
      end
    end

    module PixelFormat
      PIXELTYPE_PACKED32 = 6

      PACKEDORDER_ARGB = 3
      PACKEDORDER_BGRA = 8

      PACKEDLAYOUT_8888 = 6

      def self.define_pixelformat(type, order, layout, bits, bytes)
        (1      << 28) |
        (type   << 24) |
        (order  << 20) |
        (layout << 16) |
        (bits   <<  8) |
        (bytes  <<  0)
      end

      ARGB8888 = define_pixelformat(PIXELTYPE_PACKED32, PACKEDORDER_ARGB, PACKEDLAYOUT_8888, 32, 4)
      BGRA8888 = define_pixelformat(PIXELTYPE_PACKED32, PACKEDORDER_BGRA, PACKEDLAYOUT_8888, 32, 4)
    end

    module TextureAccess
      STREAMING = 1
    end

    class Video
      def initialize(win)
        @renderer = SDL2.CreateRenderer(win.as_ptr, -1, 0)
        pixels = FFI::MemoryPointer.new(:uint32)
        pixels.write_int32(0x04030201)
        format =
          case pixels.read_bytes(4).unpack("C*")
          when [1, 2, 3, 4] then PixelFormat::ARGB8888
          when [4, 3, 2, 1] then PixelFormat::BGRA8888
          else raise "Unknown endian"
          end

        @texture = SDL2.CreateTexture(
          @renderer,
          format,
          TextureAccess::STREAMING,
          Hongbai::SCREEN_WIDTH,
          Hongbai::SCREEN_HEIGHT
        )
        @buf = FFI::MemoryPointer.new(:uint32, Hongbai::SCREEN_WIDTH * Hongbai::SCREEN_HEIGHT)
      end

      def display(colors)
        @buf.write_array_of_uint32 colors
        SDL2.UpdateTexture(@texture, nil, @buf, Hongbai::SCREEN_WIDTH * 4)
        SDL2.RenderClear(@renderer)
        SDL2.RenderCopy(@renderer, @texture, nil, nil)
        SDL2.RenderPresent(@renderer)
      end
    end
  end
end
