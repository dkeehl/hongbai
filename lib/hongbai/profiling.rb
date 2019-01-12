require './cpu'
require './ppu'
require './mem'
require './dummy'
require './rom'
require './nes'
require 'ruby-prof'
require 'benchmark'

module Hongbai
  class NoSDL < Nes
    def self.run_profiling(path)
      if rom = INes.from_file(path)
        nes = dummy_nes(rom)
        RubyProf.start
        20_000.times { nes.step }
        res = RubyProf.stop
        printer = RubyProf::FlatPrinter.new(res)
        printer.print(STDOUT)
      end
    end

    def self.run_benchmark(path)
      if rom = INes.from_file(path)
        nes = dummy_nes(rom)
        Benchmark.bm do |x|
          x.report { 20_000.times do; nes.step end }
        end
      end
    end

    def self.dummy_nes(rom)
      win = Dummy::Window.new
      video = Dummy::Video.new(win)
      input = Dummy::Input.new
      new(rom, video, input)
    end
  end

  path = File.expand_path("../../../nes/test.nes", __FILE__)
  NoSDL.run_profiling(path)
  #NoSDL.run_benchmark(path)
end
