require_relative 'sdl/audio'

module Hongbai
  class Wav
    def self.load(file)
      File.open(file, 'r') do |f|
        meta = {}
        chunk_id = f.read(4)
        chunk_size = f.read(4).unpack('V')[0]
        wave_id = f.read(4)
        fmt_ck = f.read(4)
        fmt_size = f.read(4).unpack('V')[0]
        meta[:format] = f.read(2).unpack('v')[0]
        meta[:channels] = f.read(2).unpack('v')[0]
        meta[:sample_rate] = f.read(4).unpack('V')[0]
        meta[:data_rate] = f.read(4).unpack('V')[0]
        meta[:data_block_size] = f.read(2).unpack('v')[0]
        meta[:bit_per_sample] = f.read(2).unpack('v')[0]
        data_ck = f.read(4)
        meta[:data_size] = f.read(4).unpack('V')[0]
        unless chunk_id == 'RIFF' && wave_id == 'WAVE' && fmt_ck == 'fmt ' &&
            data_ck == 'data' 
          raise "Invalid file format: chunk_id #{chunk_id}, wave_id #{wave_id}, "\
            "fmt_ck #{fmt_ck}, data_ck #{data_ck}"
        end
        raise "Unsupported fmt size #{fmt_size}" if fmt_size != 16
        if chunk_size != fmt_size + meta[:data_size] + 28
          raise "Wrong size. "\
            "RIFF chunk: #{chunk_size}, fmt chunk #{fmt_size}, data chunk #{meta[:data_size]}"
        end
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
    SDL2.Init(SDL2::INIT_AUDIO)
    path = File.expand_path("../../../nes/audio.wav", __FILE__)
    Wav.load(path) do |meta, f|
      a = SDL2::Audio.new(meta[:sample_rate], meta[:bit_per_sample])

      interval = 1 # in seconds
      chunk_size = meta[:data_rate] * interval
      while data = f.read(chunk_size); a.play(data) end
      # waiting for playing the last chunk
      SDL2.Delay(interval * 1000)
      a.close
    end
  end
end
