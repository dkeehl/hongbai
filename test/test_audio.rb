require_relative 'helper'
require 'hongbai/sdl/sdl2'
require 'hongbai/backends/audio'

module Hongbai
  class Wav
    def self.load(file)
      File.open(file, 'r') do |f|
        meta = {}
        riff_id = f.read(4)
        _chunk_size = f.read(4).unpack('V')[0]
        wave_id = f.read(4)
        fmt_id = f.read(4)
        fmt_size = f.read(4).unpack('V')[0]
        meta[:format] = f.read(2).unpack('v')[0]
        meta[:channels] = f.read(2).unpack('v')[0]
        meta[:sample_rate] = f.read(4).unpack('V')[0]
        meta[:data_rate] = f.read(4).unpack('V')[0]
        meta[:data_block_size] = f.read(2).unpack('v')[0]
        meta[:bit_per_sample] = f.read(2).unpack('v')[0]
        data_id = f.read(4)
        meta[:data_size] = f.read(4).unpack('V')[0]
        unless riff_id == 'RIFF' && wave_id == 'WAVE' && fmt_id == 'fmt ' &&
            data_id == 'data' 
          raise "Invalid file format: riff_id #{riff_id}, wave_id #{wave_id}, "\
            "fmt_id #{fmt_id}, data_id #{data_id}"
        end
        raise "Unsupported fmt size #{fmt_size}" if fmt_size != 16
        # 20 = wave_id 4 + fmt_id 4 + fmt_size 4 + data_id 4 + data_size 4
        #if chunk_size != fmt_size + meta[:data_size] + 20
        #  raise "Wrong size. "\
        #    "RIFF chunk: #{chunk_size}, fmt chunk #{fmt_size}, data chunk #{meta[:data_size]}"
        #end
        if block_given?
          yield(meta, f)
        else
          return new(meta, file)
        end
      end
    end

    def initialize(meta, file)
      @meta = meta
      @file = file
    end

    def to_s
      str = "File #{@file}\n"
      @meta.each {|k, v| str += "#{k}: #{v}\n" }
      str
    end
  end

  module TestAudio
    def self.test_wav
      SDL2.Init(SDL2::INIT_AUDIO)
      path = File.expand_path("../../nes/piano.wav", __FILE__)
      Wav.load(path) do |meta, f|
        if meta[:format] != 1
          puts "Compressed WAV is not supported"
          abort
        end

        # info = ""
        # meta.each {|k, v| info.concat("#{k}: #{v}\n") }
        # puts(info)

        a = Backends::Audio::SDL.new(meta[:bit_per_sample], meta[:channels], meta[:sample_rate])
        interval = 1 # in seconds
        chunk_size = meta[:data_rate] * interval
        while data = f.read(chunk_size); a.play(data) end
        a.flush
        a.close
      end
    end

    def self.test_sound_file
      SDL2.Init(SDL2::INIT_AUDIO)
      a = Backends::Audio::SDL.new
      chunk_size = 44100 * 4
      File.open("sound") do |f|
        while data = f.read(chunk_size); a.play(data) end
        a.flush
        a.close
      end
    end

    test_sound_file
  end
end
