require_relative 'helper'
require 'hongbai/cpu'
require 'hongbai/ppu'
require 'hongbai/dummy'
require 'hongbai/rom'
require 'hongbai/nes'
require 'ruby-prof'
require 'benchmark'

module Hongbai
  class NoSDL < Nes
    def self.run_profiling(path)
      if rom = Rom.from_file(path)
        nes = dummy_nes(rom)
        nes.reset
        RubyProf.start
        20_000.times { nes.step }
        res = RubyProf.stop
        printer = RubyProf::FlatPrinter.new(res)
        printer.print(STDOUT)
      end
    end

    def self.run_benchmark(path)
      if rom = Rom.from_file(path)
        nes = dummy_nes(rom)
        nes.reset
        Benchmark.bm do |x|
          x.report { 20_000.times do; nes.step end }
        end
      end
    end

    def self.dummy_nes(rom)
      video = Dummy::Video.new
      audio = Dummy::Audio.new
      input = Dummy::Input.new
      new(rom, video, audio, input)
    end
  end

  path = File.expand_path("../../nes/test.nes", __FILE__)
  NoSDL.run_profiling(path)
  #NoSDL.run_benchmark(path)
end
