require_relative 'sdl/video'
require_relative './ppu'

module Hongbai
  module TestSDL
    SDL2.Init(SDL2::INIT_VIDEO | SDL2::INIT_TIMER)
    win = SDL2::Window.create("test",
                             SDL2::Window::POS_CENTERED,
                             SDL2::Window::POS_CENTERED,
                             SCREEN_WIDTH, SCREEN_HEIGHT, 0)
    @renderer = win.create_renderer(-1, 0)
    red = [255, 0, 0]
    green = [0, 255, 0]
    blue = [0, 0, 255]

    def self.draw(color)
      @renderer.draw_color = color
      (0...SCREEN_HEIGHT).each do |h|
        (0...SCREEN_WIDTH).each do |w|
          @renderer.draw_point(w, h)
        end
      end
      @renderer.present
    end

    [red, green, blue].each do |color|
      draw color
      sleep 2
    end

    win.destroy
    SDL2.Quit
  end
end
