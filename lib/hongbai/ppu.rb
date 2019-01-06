require_relative 'sdl/video'
require 'matrix'

module Hongbai
  SCREEN_WIDTH = 256
  SCREEN_HEIGHT = 240

  # TODO:
  # ** Odd and even frames
  # ** Leftmost pixles render control
  # ** Color emphasize and grey scale display
 
  class Ppu
    VRAM_ADDR_INC = [1, 32]
    SPRITE_PATTERN_TAB_ADDR = [0, 0x1000]
    NAME_TABLE_BASE = [0x2000, 0x2400, 0x2800, 0x2c00]

    def initialize(rom, driver, context)
      @context = context
      @renderer = driver
      @vram = Vram.new(rom)
      @rom = rom
      @oam = Oam.new
      @oam2 = Oam2.new
      # A buffer that computes color priority and checks sprite 0 hit.
      @buffer = Output.new

      # Registers
      # PPU_CTRL
      @name_table_base = 0x2000
      @vram_addr_increment = 1
      @sprite_pattern_table_addr = 0
      @bg_pattern_table_addr = 0
      @sprite_8x16_mode = false
      @sprite_height = 8
      @generate_vblank_nmi = false
      # PPU_MASK
      @gray_scale = false
      @show_leftmost_8_bg = false
      @show_leftmost_8_sprite = false
      @show_background = false
      @show_sprites = false
      @emphasize_red = false
      @emphasize_green = false
      @emphasize_blue = false
      # PPU_STATUS
      @ppu_status = 0
      # PPU_SCROLL
      @scroll_x = 0
      @scroll_y = 0
      # PPU_ADDR
      @ppu_addr =0
      @scanline = 0
      @x = 0
      @toggle = false
      @ppu_data_read_buffer = 0

      # TODO: This is a hack to speed up. But it doesn't work with all mappers
      @pattern_table = Matrix.build(512, 8) {|row, col| build_tile(row, col) }

      @screen = Array.new(SCREEN_WIDTH * SCREEN_HEIGHT, 0xffffffff)
      @screen_offset = 0

      @main_loop = Fiber.new { run_main_loop }

      @frame = 0
      @trace = false
    end

    attr_reader :frame, :scanline, :main_loop

    def run_main_loop
      loop do
        # scanline 0 to 239
        0.step(239) do
          render_scanline
          @scanline += 1
          Fiber.yield
        end

        # scanline 240
        Fiber.yield

        # scanline 241
        set_vblank_start
        Fiber.yield(@generate_vblank_nmi)

        # scanline 242 to 260
        242.step(260) { Fiber.yield }

        # pre-render line
        set_vblank_end
        @renderer.display @screen
        @screen_offset = 0
        @scanline = 0
        @frame += 1
        @context.on_new_frame
        Fiber.yield
      end
    end

    def read_oam_data(_addr)
      @oam.read
    end

    def read_ppu_status(_addr)
      @toggle = false
      @ppu_status
    end

    def read_ppu_data(_addr)
      # Mirror down addresses greater than 0x3fff
      addr = @ppu_addr & 0x3fff
      val = @vram.read(addr)
      @ppu_addr += @vram_addr_increment
      buffered = @ppu_data_read_buffer
      @ppu_data_read_buffer = val

      addr < 0x3f00 ? buffered : val
    end

    def write_ppu_ctrl(_addr, val)
      @name_table_base           = NAME_TABLE_BASE[val & 3]
      @vram_addr_increment       = VRAM_ADDR_INC[val[2]]
      @sprite_pattern_table_addr = SPRITE_PATTERN_TAB_ADDR[val[3]]
      @bg_pattern_table_addr     = val[4]
      @sprite_8x16_mode          = val[5] == 1
      @generate_vblank_nmi       = val[7] == 1

      @sprite_height = @sprite_8x16_mode ? 16 : 8
    end

    def write_ppu_mask(_addr, val)
      @gray_scale             = val[0] == 1
      @show_leftmost_8_bg     = val[1] == 1
      @show_leftmost_8_sprite = val[2] == 1
      @show_background        = val[3] == 1
      @show_sprites           = val[4] == 1
      @emphasize_red          = val[5] == 1
      @emphasize_green        = val[6] == 1
      @emphasize_blue         = val[7] == 1
    end

    def write_oam_addr(_addr, val)
      @oam.addr = val
    end

    # Public for OAM DMA
    def write_oam_data(_addr, val)
      @oam.write val
    end

    def write_ppu_scroll(_addr, val)
      if @toggle # toggle is true, the second write
        @scroll_y = val
      else
        @scroll_x = val
      end
      @toggle = !@toggle
    end

    def write_ppu_addr(_addr, val)
      if @toggle
        @ppu_addr = @ppu_addr & 0xff00 | val
      else
        @ppu_addr = @ppu_addr & 0x00ff | (val << 8)
        # This is a hack
        @name_table_base = NAME_TABLE_BASE[(@ppu_addr >> 10) & 3]
      end
      @toggle = !@toggle
    end

    def write_ppu_data(_addr, val)
      # Mirror down addresses greater than 0x3fff
      addr = @ppu_addr & 0x3fff
      @vram.write(addr, val)
      @ppu_addr += @vram_addr_increment
    end

    private
      # Ppu -> Integer -> Integer -> Tile
      # A Tile is a 8*8 Matrix of Color
      def build_tile(row, col)
        # The pattern table lays in the VRAM from $0000 to $1fff,
        # including 512 tiles, each of 16 bytes, devided into two
        # 8 bytes planes.
        plane0 = Array.new(8) { |i| @vram.read(row * 16 + i) }
        plane1 = Array.new(8) { |i| @vram.read(row * 16 + 8 + i) }
        # make either plane a 8*8 matrix of bit
        plane0 = Matrix.build(8) { |r, c| (plane0[r] >> (7 - c)) & 1 }
        plane1 = Matrix.build(8) { |r, c| (plane1[r] >> (7 - c)) & 1 }
        # plane0 controls the 0 bit of color index,
        # plane1 controls the 1 bit whild the attribute controls the higher 2 bits
        tile = plane0 + plane1 * Matrix.scalar(8, 2)
        attribute = col << 2
        tile.map {|i| i.zero? ? 0 : (i | attribute) }
      end

      # Ppu -> Nil
      def render_scanline
        # evaluate sprite info for next scanline
        sprite_evaluation
        # nametable y index
        y_idx = (@scroll_y + @scanline) / 8
        # nametable x index
        x_idx = (@scroll_x + @x) / 8
        nametable = @name_table_base

        tile_internal_y_offset = (@scroll_y  + @scanline) % 8
        tile_internal_x_offset = @scroll_x % 8

        unless tile_internal_x_offset.zero?
          first_tile = true
          first = (tile_internal_x_offset..7)
          last = (0...tile_internal_x_offset)
        end

        while @x < SCREEN_WIDTH
          attribute = get_attribute(nametable, x_idx, y_idx)
          tile_num = @vram.read(nametable + y_idx * 32 + x_idx)
          tile = @pattern_table[@bg_pattern_table_addr * 256 + tile_num, attribute]
          pattern = tile.row(tile_internal_y_offset)

          if first
            if first_tile
              render_tile_line(pattern, first)
              first_tile = false
            elsif @x > 247
              render_tile_line(pattern, last)
              break
            else
              render_tile_line pattern
            end
          else
            render_tile_line pattern
          end

          x_idx += 1
          if x_idx == 32
            # nametable change
            # $2000 -> $2400 -> $2000
            # $2800 -> $2C00 -> $2800
            (nametable / 0x400).even? ? nametable += 0x400 : nametable -= 0x400
            x_idx = 0
          end
        end

        # HBlank
        # fetch sprite tiles for the next scanline
        sprite_fetch
        @x = 0
      end


      # Render a tile. (Only the current scanline)
      # Ppu -> Array<ColorIndex> -> Nil | Range -> nil
      def render_tile_line(bg_colors, range = (0..7))
        if @show_background
          if @show_sprites
            # push_bg returns true when sprite 0 hits.
            if @buffer.push_bg(bg_colors, range, @x)
              set_sprite_zero_hit(true)
              #raise "frame #{@frame}, scanline #{@scanline}"
            end
            range.each { put_pixel(@buffer[@x]); @x += 1 }
          else
            # Sprite rendering is disabled.
            range.each {|i| put_pixel(bg_colors[i]); @x += 1 }
          end
        elsif @show_sprites
          # Background rendering is disabled.
          range.each { put_pixel(@buffer[@x]); @x += 1 }
        else
          # Both background and pixel rendering are disabled.
          range.each { put_pixel(0); @x += 1 }
        end
      end
 
      ATTR_TABLE = (0..0xff).map do |val|
        # map each u8 value to an arrary of 30 * 32 = 960 attributes
        arr = []
        (0..29).each do |y|
          (0..31).each do |x|
            arr[y * 32 + x] =
              # Every 4*4 tiles share an attribute byte
              # ________________
              # |/|/|/|/|_|_|_|_
              # |/|/|/|/|_|_|_|_
              # |/|/|/|/|_|_|_|_
              # |/|/|/|/|_|_|_|_
              # |_|_|_|_|_|_|_|_
              # |_|_|_|_|_|_|_|_
              # |_|_|_|_|_|_|_|_
              # | | | | | | | |
              #
              # Every 2 bits of an arttribute byte controls a 2*2 corner of the group of
              # 4*4 tiles
              #
              # 7654 3210
              # |||| ||++- topleft corner
              # |||| ++--- topright corner
              # ||++ ----- bottomleft corner
              # ++-- ----- bottomright corner
              if y % 4 < 2
                if x % 4 < 2 # topleft
                  val & 3
                else # topright
                  (val >> 2) & 3
                end
              else
                if x % 4 < 2 # bottomleft
                  (val >> 4) & 3
                else # topright
                  (val >> 6) & 3
                end
              end
          end
        end
        arr
      end

      # Ppu -> Integer -> Integer -> Integer -> Integer
      def get_attribute(nametable_base, x_idx, y_idx)
        # load the attribute
        offset = y_idx / 4 * 8 + x_idx / 4
        attr_byte = @vram.read(nametable_base + 0x3c0 + offset)
        ATTR_TABLE[attr_byte][y_idx * 32 + x_idx]
      end

      # Ppu -> nil
      def sprite_evaluation
        @oam2.init

        # TODO: use OAMADDR to start
        y = @oam[0]
        @oam2.insert(y)
        if sprite_on_scanline(y)
          1.upto(3) { |i| @oam2.push(@oam[i]) }
          @oam2.has_sprite_zero = true
        end

        n = 1
        loop do
          y = @oam[n * 4]
          @oam2.insert(y)
          if sprite_on_scanline(y)
            1.upto(3) { |i| @oam2.push(@oam[n * 4 + i]) }
          end
          n += 1
          return if n == 64

          break if @oam2.full?
        end

        m = 0
        while n < 64
          y = @oam[n * 4 + m]
          if sprite_on_scanline(y)
            set_sprite_overflow(true)
            break
          else
            n += 1
            # the sprite overflow bug
            m = (m + 1) % 4
          end
        end
      end

      # Ppu -> Integer -> Bool
      def sprite_on_scanline(sprite_y_offset)
        sprite_y_offset <= @scanline &&
          sprite_y_offset + @sprite_height > @scanline
      end

      # Ppu -> nil
      # read oam2 data to buffer
      def sprite_fetch
        @buffer.clear
        @buffer.may_hit_sprite_0 = @oam2.has_sprite_zero

        @oam2.each_sprite do |tile, attr, flip_h, flip_v, x, y, prior, sprite0|
          y_inter = @scanline - y
          if !@sprite_8x16_mode
            # 8*8 sprite mode
            tile += @sprite_pattern_table_addr
            pattern = @pattern_table[tile, attr]
            y_inter = flip_v ? 7 - y_inter : y_inter
          else
            # 8*16 sprite mode
            tile = Ppu.to_8x16_sprite_tile_addr(tile)
            if y_inter <= 7 && !flip_v || y_inter > 7 && flip_v
              pattern = @pattern_table[tile, attr]
              y_inter = flip_v ? 15 - y_inter : y_inter
            else
              pattern = @pattern_table[tile + 1, attr]
              y_inter = flip_v ? 7 - y_inter : y_inter % 8
            end
          end

          colors = pattern.row(y_inter)
          # TODO: Can this be done without using the `to_a` operation?
          if flip_h
            colors = colors.to_a.reverse
          end
          @buffer.push_sprite(colors, x, prior, sprite0)
        end
      end

      # Integer -> Integer
      def self.to_8x16_sprite_tile_addr(tile_number)
        bank = tile_number & 1 * 256
        bank + (tile_number & 0xfe)
      end

      def put_pixel(color_index)
        @screen[@screen_offset] = @vram.palette.get_color(color_index)
        @screen_offset += 1
      end

      def set_in_vblank(b)
        b ? @ppu_status |= 0x80 : @ppu_status &= 0x7f
      end

      def set_sprite_zero_hit(b)
        b ? @ppu_status |= 0x40 : @ppu_status &= 0xbf
      end

      def set_sprite_overflow(b)
        b ? @ppu_status |= 0x20 : @ppu_status &= 0xdf
      end

      def set_vblank_start
        set_in_vblank(true)
      end

      # Ppu -> Nil
      def set_vblank_end
        set_in_vblank(false)
        set_sprite_zero_hit(false)
        set_sprite_overflow(false)
      end
  end

  class Oam
    def initialize
      @arr = Array.new(256, 0)
      @addr = 0
    end

    attr_writer :addr

    def read
      @arr[@addr]
    end

    def write(val)
      @arr[@addr] = val
      @addr = (@addr + 1) & 0xff
    end

    def [](n)
      @arr[n]
    end

    def []=(n, x)
      @arr[n] = x
    end
    
    def to_s
      str = ""
      i = 0
      while i < 64
        y = @arr[i * 4]
        if y > 240 || y.zero?
          break
        else
          num = @arr[i * 4 + 1]
          x = @arr[i * 4 + 3]
          str += "\##{num} (#{x}, #{y}) "
          i += 1
        end
      end
      str
    end
  end

  class Oam2
    def initialize
      @arr = Array.new(8 * 4, 0xff)
      @cursor = 0
      @openslot = 0
      @push_count = 0
      @has_sprite_zero = false
    end

    attr_accessor :has_sprite_zero

    def init
      @arr.map! { 0xff }
      @cursor = 0
      @openslot = 0
      @push_count = 0
      @has_sprite_zero = false
    end

    # Oam2 -> Integer -> Nil
    def push(n)
      @arr[@cursor] = n
      @cursor += 1
      @openslot = @cursor
      @push_count += 1
    end

    # Oam2 -> Integer -> Nil
    # overide previous inserted element, if no push happened after that insertion
    def insert(n)
      @arr[@openslot] = n
      @cursor = @openslot + 1
    end

    # Oam2 -> Bool
    def full?
      @push_count >= 24 # 8 sprites, each 3 pushes
    end

    # Iterate over sprites
    def each_sprite
      count = 0
      if @has_sprite_zero
        tile, attr, flip_h, flip_v, x, y, prior = take_at(0)
        yield(tile, attr, flip_h, flip_v, x, y, prior, true)
        count += 1
      end

      while count * 3 < @push_count
        tile, attr, flip_h, flip_v, x, y, prior = take_at(count)
        yield(tile, attr, flip_h, flip_v, x, y, prior, false)
        count += 1
      end
    end

    private
      # Oam2 -> Integer -> (Integer, Integer, Bool, Bool, Integer, Integer, Bool)
      def take_at(count)
        tile = @arr[count * 4 + 1]
        y = @arr[count * 4]
        x = @arr[count * 4 + 3]

        attributes = @arr[count * 4 + 2]
        attr = (attributes & 3) + 4
        prior = (attributes & 0x20).zero?
        flip_h = (attributes & 0x40) != 0
        flip_v = (attributes & 0x80) != 0
        return tile, attr, flip_h, flip_v, x, y, prior
      end
  end

  class Vram
    def initialize(rom)
      @rom = rom
      @palette = Palette.new

      @read_map = Array.new(0x4000)
      @write_map = Array.new(0x4000)
      init_memory_map
    end

    attr_reader :palette

    def init_memory_map
      # Memory map
      # $0000 - $1fff pattern table (rom)
      (0..0x1fff).each do |i|
        @read_map[i] = @rom.chr_read_method
        @write_map[i] = @rom.chr_write_method
      end
      # $2000 - $2fff 4 nametables
      # $3000 - $3eff mirrors of $2000 - $2eff
      (0x2000..0x3eff).each do |i|
        @read_map[i] = @rom.mirroring.ram_read_method(i)
        @write_map[i] = @rom.mirroring.ram_write_method(i)
      end
      # $3f00 - $3f1f palette
      # $3f20 - $3fff mirrors of $3f00 - $3f1f
      (0x3f00..0x3fff).each do |i|
        @read_map[i] = @palette.method(:load)
        @write_map[i] = @palette.method(:store)
      end
    end

    def read(addr)
      @read_map[addr][addr]
    end

    def write(addr, val)
      @write_map[addr][addr, val]
    end
  end

  class Output
    Item = Struct.new(:color, :from_sprite_0, :above_bg)

    def initialize
      @may_hit_sprite_0 = false
      @items = Array.new(SCREEN_WIDTH) { Item.new(0, nil, nil) }
    end

    attr_accessor :may_hit_sprite_0

    def clear
      @may_hit_sprite_0 = false
      @items.each do |i|
        i.color = 0 
        i.from_sprite_0 = nil
        i.above_bg = nil
      end
    end

    # Output -> Integer -> ColorIndex
    def [](n)
      @items[n].color
    end

    # Output -> Array<ColorIndex> -> Integer -> Bool -> Bool -> Nil
    # where colors.length == 8
    def push_sprite(colors, x_offset, above_bg, from_sprite_0)
      i = x_offset
      colors.each do |c|
        item = @items[i]
        if item && (item.color.zero? || (above_bg && !item.above_bg))
          item.color = c
          item.from_sprite_0 = from_sprite_0
          item.above_bg = above_bg
        end
        i += 1
      end
    end

    # Output -> Array<ColorIndex> -> Range -> Integer -> Bool
    # Return true if sprite 0 hits, return false otherwise.
    def push_bg(colors, range, x_offset)
      i = x_offset
      if @may_hit_sprite_0
        # Only checks when sprite 0 is included in this render
        hit = false
        range.each do |n|
          item = @items[i]
          c = colors[n]
          if item.from_sprite_0 && !item.color.zero? && !c.zero? && i != 255
            hit = true
          end
          push_bg_color(c, i)
          i += 1
        end
        hit
      else
        range.each do |n|
          c = colors[n]
          push_bg_color(c, i)
          i += 1
        end
        false
      end
    end

    private
      # Output -> ColorIndex -> Integer -> Nil
      # Insert a background color at the index
      def push_bg_color(color, index)
        item = @items[index]
        unless !item.color.zero? && item.above_bg || color.zero?
          @items[index].color = color
        end
      end
  end

  class Palette
    PALETTE = [
      [124,124,124],    [0,0,252],        [0,0,188],        [68,40,188],
      [148,0,132],      [168,0,32],       [168,16,0],       [136,20,0],
      [80,48,0],        [0,120,0],        [0,104,0],        [0,88,0],
      [0,64,88],        [0,0,0],          [0,0,0],          [0,0,0],
      [188,188,188],    [0,120,248],      [0,88,248],       [104,68,252],
      [216,0,204],      [228,0,88],       [248,56,0],       [228,92,16],
      [172,124,0],      [0,184,0],        [0,168,0],        [0,168,68],
      [0,136,136],      [0,0,0],          [0,0,0],          [0,0,0],
      [248,248,248],    [60,188,252],     [104,136,252],    [152,120,248],
      [248,120,248],    [248,88,152],     [248,120,88],     [252,160,68],
      [248,184,0],      [184,248,24],     [88,216,84],      [88,248,152],
      [0,232,216],      [120,120,120],    [0,0,0],          [0,0,0],
      [252,252,252],    [164,228,252],    [184,184,248],    [216,184,248],
      [248,184,248],    [248,164,192],    [240,208,176],    [252,224,168],
      [248,216,120],    [216,248,120],    [184,248,184],    [184,248,216],
      [0,252,252],      [248,216,248],    [0,0,0],          [0,0,0]
    ].map {|r, g, b| (0xff << 24) | (r << 16) | (g << 8) | b }
   
    Item = Struct.new(:val, :color)

    def initialize
      # rus from $3f00 to $3f1f, 32 bytes
      @items = Array.new(32) { Item.new(0, 0xffffffff) }
      # Mirroring
      [0x10, 0x14, 0x18, 0x1c].each do |addr|
        @items[addr] = @items[addr - 0x10]
      end
    end

    def get_color(color_index)
      @items[color_index].color
    end

    def load(addr)
      @items[addr & 0x1f].val
    end

    def store(addr, val)
      item = @items[addr & 0x1f]
      item.val = val
      item.color = PALETTE[val & 0x3f]
    end
  end
end
