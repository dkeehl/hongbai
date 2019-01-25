require_relative 'helper'
require 'hongbai/ppu_address'
require 'minitest/autorun'

class Hongbai::Address
  attr_accessor :val
end

class TestAddr < MiniTest::Test
  def setup
    @addr = Hongbai::Address.new
  end

  def test_attr_readers
    @addr.val = 0b100_0110_1010_1010
    assert_equal(@addr.fine_y_offset, 0b100)
    assert_equal(@addr.nametable_y, 0)
    assert_equal(@addr.nametable_x, 1)
    assert_equal(@addr.coarse_y_offset, 0b10101)
    assert_equal(@addr.coarse_x_offset, 0b1010)
  end

  def test_attr_writers
    @addr.fine_y_offset = 5
    @addr.nametable_y = 1
    @addr.nametable_x = 0
    @addr.coarse_y_offset = 9
    @addr.coarse_x_offset = 30
    assert_equal(@addr.fine_y_offset, 5)
    assert_equal(@addr.nametable_y, 1)
    assert_equal(@addr.nametable_x, 0)
    assert_equal(@addr.coarse_y_offset, 9)
    assert_equal(@addr.coarse_x_offset, 30)
  end

  def test_nametable_switch
    mask = 0b111_0011_1111_1111
    before = @addr.val & mask

    assert_equal(0, @addr.nametable_y)
    assert_equal(0, @addr.nametable_x)
    @addr.switch_h
    @addr.switch_v
    assert_equal(1, @addr.nametable_x)
    assert_equal(1, @addr.nametable_y)
    assert_equal(before, @addr.val & mask)
    @addr.switch_h
    @addr.switch_v
    assert_equal(0, @addr.nametable_y)
    assert_equal(0, @addr.nametable_x)
    assert_equal(before, @addr.val & mask)
  end

  def test_x_inc
    @addr.coarse_x_offset = 1
    nt = @addr.nametable_x
    @addr.coarse_x_increment
    assert_equal(2, @addr.coarse_x_offset)
    assert_equal(nt, @addr.nametable_x)

    @addr.coarse_x_offset = 31
    nt = @addr.nametable_x
    @addr.coarse_x_increment
    assert_equal(0, @addr.coarse_x_offset)
    refute_equal(nt, @addr.nametable_x)
  end

  def test_y_inc
    @addr.fine_y_offset = 6
    y = @addr.coarse_y_offset
    nt = @addr.nametable_y
    @addr.y_increment
    assert_equal(7, @addr.fine_y_offset)
    assert_equal(y, @addr.coarse_y_offset)
    assert_equal(nt, @addr.nametable_y)

    @addr.coarse_y_offset = 28
    @addr.y_increment
    assert_equal(0, @addr.fine_y_offset)
    assert_equal(29, @addr.coarse_y_offset)
    assert_equal(nt, @addr.nametable_y)

    @addr.fine_y_offset = 7
    @addr.y_increment
    assert_equal(0, @addr.fine_y_offset)
    assert_equal(0, @addr.coarse_y_offset)
    refute_equal(nt, @addr.nametable_y)
  end

  def test_tile_address
    (0..3).each do |nametable|
      @addr.nametable_x = nametable & 1
      @addr.nametable_y = (nametable >> 1) & 1
      (0..31).each do |x|
        (0..29).each do |y|
          addr = 0x2000 + nametable * 0x400 + y * 32 + x
          @addr.coarse_y_offset = y
          @addr.coarse_x_offset = x
          assert_equal(addr, @addr.tile)
        end
      end
    end
  end

  def test_attribute_address
    (0..3).each do |nametable|
      @addr.nametable_x = nametable & 1
      @addr.nametable_y = (nametable >> 1) & 1
      (0..31).each do |x|
        (0..29).each do |y|
          x_attr = x / 4
          y_attr = y / 4
          addr = 0x23c0 + nametable * 0x400 + y_attr * 8 + x_attr
          @addr.coarse_y_offset = y
          @addr.coarse_x_offset = x
          assert_equal(addr, @addr.attribute)
        end
      end
    end
  end
end

