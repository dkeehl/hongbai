require_relative './sdl2'

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

      def destroy
        SDL2.DestroyWindow(@win_ptr)
      end

      def create_renderer(index, flags)
        renderer = SDL2.CreateRenderer(@win_ptr, index, flags)
        Renderer.new renderer
      end
    end

    class Renderer
      def initialize(renderer_ptr)
        @ptr = renderer_ptr
      end

      def draw_color=(color)
        SDL2.SetRenderDrawColor(@ptr, color[0], color[1], color[2], 255)
      end

      def draw_point(x, y)
        SDL2.RenderDrawPoint(@ptr, x, y)
      end

      def present
        SDL2.RenderPresent(@ptr)
      end
    end
  end
end
