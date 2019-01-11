module Hongbai
  class Address
    FINE_Y_OFFSET_FIT = 0b111
    FINE_Y_OFFSET_OFFSET = 12
    FINE_Y_OFFSET_MASK = 0xfff

    NAMETABLE_Y_FIT = 1
    NAMETABLE_Y_OFFSET = 11
    NAMETABLE_Y_MASK = 0b111_0111_1111_1111

    NAMETABLE_X_FIT = 1
    NAMETABLE_X_OFFSET = 10
    NAMETABLE_X_MASK = 0b111_1011_1111_1111

    COARSE_Y_OFFSET_FIT = 0b1_1111
    COARSE_Y_OFFSET_OFFSET = 5
    COARSE_Y_OFFSET_MASK = 0b111_1100_0001_1111

    COARSE_X_OFFSET_FIT = 0b1_1111
    COARSE_X_OFFSET_OFFSET = 0
    COARSE_X_OFFSET_MASK = 0b111_1111_1110_0000

    names = %w[fine_y_offset nametable_y nametable_x coarse_y_offset coarse_x_offset]
    names.each do |name|
      fit = const_get("#{name.upcase}_FIT".to_sym)
      mask = const_get("#{name.upcase}_MASK".to_sym)
      offset = const_get("#{name.upcase}_OFFSET".to_sym)

      get = "(@val >> #{offset}) & #{fit}"
      set = "@val = (@val & #{mask}) ^ (x << #{offset})"
      class_eval("def #{name}; #{get} end\n"\
                 "def #{name}=(x); #{set} end")
    end

    def initialize
      @val = 0
    end

    def switch_h
      #self.nametable_x ^= 1
      @val ^= 0b100_0000_0000
    end

    def switch_v
      #self.nametable_y ^= 1
      @val ^= 0b1000_0000_0000
    end

    def coarse_x_increment
      if self.coarse_x_offset == 31
        # self.coarse_x_offset = 0
        # switch_h
        @val ^= 0b100_0001_1111
      else
        @val += 1
      end
    end

    def y_increment
      fine_y = self.fine_y_offset
      if fine_y < 7
        # self.fine_y_offset = fine_y + 1
        @val += 0x1000
      else
        # self.fine_y_offset = 0
        @val &= 0xfff
        y = self.coarse_y_offset
        if y == 29
          # self.coarse_y_offset = 0
          # switch_v
          @val ^= 0b1011_1010_0000
        elsif y == 31
          # self.coarse_y_offset = 0
          @val ^= 0b11_1110_0000
        else
          # self.coarse_y_offset = y + 1
          @val += 32
        end
      end
    end

    def copy_x(other)
      self.nametable_x = other.nametable_x
      self.coarse_x_offset = other.coarse_x_offset
    end

    def copy_y(other)
      self.fine_y_offset = other.fine_y_offset
      self.nametable_y = other.nametable_y
      self.coarse_y_offset = other.coarse_y_offset
    end

    def copy(other)
      @val = other.to_i
    end

    # Into the address of the tile which this address points to 
    def tile
      0x2000 | (@val & 0xfff)
    end

    ATTR_ADDRS = (0..0xfff).map do |pos|
      y, x = pos.divmod(32)
      (y / 4) * 8 + (x / 4)
    end

    # Into the address of the tile's attribute
    # NN11 11YY YXXX
    # |||| |||| |+++ - high 3 bits of coarse x
    # |||| ||++ +--- - high 3 bits of coarse y
    # ||++ ++-- ---- - attribute offset
    # ++-- ---- ---- - nametable
    def attribute
      0x23c0 | (@val & 0xc00) | # 0xc00 takes the 2 nametable bits
      ATTR_ADDRS[@val & 0xfff]
    end

    def add(n)
      @val += n
    end

    def to_i; @val end
  end

  class TempAddress
    def initialize
      @nametable_x = 0
      @nametable_y = 0
      @coarse_x_offset = 0
      @coarse_y_offset = 0
      @fine_y_offset = 0
    end

    attr_accessor :nametable_x, :nametable_y, :coarse_x_offset, :coarse_y_offset, :fine_y_offset

    def update_lo(val)
      @coarse_x_offset = val & 0x1f
      @coarse_y_offset = @coarse_y_offset & 0x18 | (val >> 5)
    end

    def update_hi(val)
      @coarse_y_offset = @coarse_y_offset & 7 | ((val & 3) << 3)
      @nametable_x = val[2]
      @nametable_y = val[3]
      @fine_y_offset = (val >> 4) & 3
    end

    def to_i
      (@fine_y_offset << 12) | (@nametable_y << 11) | (@nametable_x << 10) |
      (@coarse_y_offset << 5) | @coarse_x_offset
    end
  end
end
