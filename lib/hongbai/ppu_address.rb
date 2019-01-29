module Hongbai
  class Address
    def initialize
      @tmp_nametable_x = 0
      @tmp_nametable_y = 0
      @tmp_coarse_x_offset = 0
      @tmp_coarse_y_offset = 0
      @tmp_fine_y_offset = 0

      @val = 0
    end

    attr_writer :tmp_nametable_x, :tmp_nametable_y, :tmp_fine_y_offset,
                :tmp_coarse_x_offset, :tmp_coarse_y_offset 

    def update_lo(val)
      @tmp_coarse_x_offset = val & 0x1f
      @tmp_coarse_y_offset = @tmp_coarse_y_offset & 0x18 | (val >> 5)
    end

    def update_hi(val)
      @tmp_coarse_y_offset = @tmp_coarse_y_offset & 7 | ((val & 3) << 3)
      @tmp_nametable_x     = val[2]
      @tmp_nametable_y     = val[3]
      @tmp_fine_y_offset   = (val >> 4) & 3
    end

    def fine_y_offset
      @val >> 12
    end

    def coarse_x_increment
      # if coarse_x_offset == 31
      if @val & 0x1f == 31
        # coarse_x_offset = 0
        # switch_h
        @val ^= 0b100_0001_1111
      else
        @val += 1
      end
    end

    def y_increment
      fine_y = @val >> 12
      if fine_y < 7
        # fine_y_offset = fine_y + 1
        @val += 0x1000
      else
        # fine_y_offset = 0
        @val &= 0xfff
        # coarse_y_offset
        y = (@val >> 5) & 0x1f
        if y == 29
          # coarse_y_offset = 0
          # switch_v
          @val ^= 0b1011_1010_0000
        elsif y == 31
          # coarse_y_offset = 0
          @val ^= 0b11_1110_0000
        else
          # coarse_y_offset = y + 1
          @val += 32
        end
      end
    end

    def copy_x
      # nametable_x = @tmp_nametable_x
      # coarse_x_offset = @tmp_coarse_x_offset
      @val = (@val & 0b111_1011_1110_0000) | (@tmp_nametable_x << 10) | @tmp_coarse_x_offset
    end

    def copy_y
      # fine_y_offset = @tmp_fine_y_offset
      # nametable_y = @tmp_nametable_y
      # coarse_y_offset = @tmp_coarse_y_offset
      @val = (@val & 0b100_0001_1111) | (@tmp_fine_y_offset << 12) |
        (@tmp_nametable_y << 11) | (@tmp_coarse_y_offset << 5)
    end

    def copy_tmp
      @val =
        (@tmp_fine_y_offset   << 12) |
        (@tmp_nametable_y     << 11) |
        (@tmp_nametable_x     << 10) |
        (@tmp_coarse_y_offset <<  5) |
         @tmp_coarse_x_offset
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

    def palette
      @val & 0x3fff < 0x3f00 ? 0 : @val & 0x1f
    end

    def add(n)
      @val += n
    end

    def pos_in_nametable; @val & 0x3ff end

    def to_i; @val & 0x3fff end
  end
end
