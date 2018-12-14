require 'sdl2'
require './input'

module TestInput
  SDL2.init(SDL2::INIT_EVENTS | SDL2::INIT_VIDEO)
  _win = SDL2::Window.create("test", 300, 300, 100, 100, 0)
  key_map = Hongbai::KeyMap.default_1p
  controller = Hongbai::Controller.new(key_map)
  input = Hongbai::Input.new(controller)
  loop do
    input.poll
    input.store 1
    input.store 0
    puts "A: #{input.read_4016}"
    puts "B: #{input.read_4016}"
    puts "SELECT: #{input.read_4016}"
    puts "START: #{input.read_4016}"
    puts "UP: #{input.read_4016}"
    puts "DOWN: #{input.read_4016}"
    puts "LEFT: #{input.read_4016}"
    puts "RIGHT: #{input.read_4016}"
    puts "-------------------------"

    sleep 0.01
  end
end
