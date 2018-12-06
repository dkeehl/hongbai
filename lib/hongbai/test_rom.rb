require 'minitest/autorun'
require_relative './rom'

class RomTest < MiniTest::Test
  def test_file_load_ok
    path = File.expand_path('../../../nes/test.nes', __FILE__)
    rom = Hongbai::INes.from_file(path)
    #puts rom.inspect
    assert(!rom.nil?)
    # mapper test
    methods = rom.methods
    [:next_scanline_irq, :prg_load, :prg_store, :chr_load, :chr_store].each do |m|
      assert(methods.include?(m), "#{m} not defined")
    end

    assert(rom.instance_variable_defined?(:@prg_addr_mask))
  end

  def test_file_load_fail
    path = File.expand_path('../../../nes/6502_functional_test.bin', __FILE__)
    rom = Hongbai::INes.from_file(path)
    assert(rom.nil?)
  end
end
