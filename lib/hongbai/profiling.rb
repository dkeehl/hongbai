require './cpu'
require './ppu'
require './mem'
require './dummy'
require './rom'
require './nes'
require 'ruby-prof'

module Hongbai
  class NoSDL < Nes
    def self.run(path)
      if rom = INes.from_file(path)
        win = Dummy::Window.new
        input = Dummy::Input.new

        ppu = Ppu.new(rom, win)
        mem = Memory.new(ppu, rom, input)
        cpu = Cpu.new(mem)
        nes = new(cpu, ppu, mem, input)
        RubyProf.start
        20_000.times { nes.step }
        res = RubyProf.stop
        printer = RubyProf::FlatPrinter.new(res)
        printer.print(STDOUT)
      end
    end
  end

  path = File.expand_path("../../../nes/test.nes", __FILE__)
  NoSDL.run(path)
end
