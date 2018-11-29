require 'minitest/autorun'
require_relative './ppu'

class ColorTest < MiniTest::Test
  def test_color_order
    bd = Hongbai::BDColor.new(0, 0, 0)
    bg = Hongbai::BGColor.new(0, 0, 0)
    sprite_a = Hongbai::SpriteColorAbove.new(0, 0, 0)
    sprite_b = Hongbai::SpriteColorBelow.new(0, 0, 0)

    assert_equal(bd | nil, bd)
    assert_equal(bg | nil, bg)
    assert_equal(sprite_a | nil, sprite_a)
    assert_equal(sprite_b | nil, sprite_b)

    assert_equal(bd | bg, bg)
    assert_equal(bd | sprite_a, sprite_a)
    assert_equal(bd | sprite_b, sprite_b)

    assert_equal(bg | bd, bg)
    assert_equal(bg | sprite_b, bg)
    assert_equal(bg | sprite_a, sprite_a)

    assert_equal(sprite_a | bd, sprite_a)
    assert_equal(sprite_a | bg, sprite_a)
    assert_equal(sprite_a | sprite_b, sprite_a)

    assert_equal(sprite_b | bd, sprite_b)
    assert_equal(sprite_b | bg, bg)
    assert_equal(sprite_b | sprite_a, sprite_a)
  end

end
