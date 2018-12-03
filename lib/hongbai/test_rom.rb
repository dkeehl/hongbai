require_relative './rom'

module Hongbai
  path = File.expand_path('../../../nes/test.nes', __FILE__)
  rom = INes.from_file(path)
  puts rom.inspect
end
