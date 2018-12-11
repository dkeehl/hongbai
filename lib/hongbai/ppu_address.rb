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
      self.nametable_x ^= 1
    end

    def switch_v
      self.nametable_y ^= 1
    end

    def coarse_x_increment
      if self.coarse_x_offset == 31
        self.coarse_x_offset = 0
        switch_h
      else
        @val += 1
      end
    end

    def y_increment
      fine_y = self.fine_y_offset
      if fine_y < 7
        self.fine_y_offset = fine_y + 1
      else
        self.fine_y_offset = 0
        y = self.coarse_y_offset
        if y == 29
          self.coarse_y_offset = 0
          switch_v
        elsif y == 31
          self.coarse_y_offset = 0
        else
          self.coarse_y_offset = y + 1
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

    # Into the address of the tile's attribute
    # NN11 11YY YXXX
    # |||| |||| |+++ - high 3 bits of coarse x
    # |||| ||++ +--- - high 3 bits of coarse y
    # ||++ ++-- ---- - attribute offset
    # ++-- ---- ---- - nametable
    def attribute
      0x23c0 | (@val & 0xc00) | # 0xc00 takes the 2 nametable bits
      ((self.coarse_y_offset << 1) & 0x38) | (self.coarse_x_offset >> 2)
    end

    def add(n)
      @val += n
    end

    def to_i; @val end
  end
end
