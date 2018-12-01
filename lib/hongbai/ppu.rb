require 'sdl2'
require 'matrix'

module Hongbai
  SCREEN_WIDTH = 256
  SCREEN_HEIGHT = 240

  class Ppu
    # A scanline is 341 ppu clocks
    # Ppu runs at 3 times the cpu clock rate
    CYCLES_PER_SCANLINE = 114 
    VBLANK_SCANLINE = 241
    LAST_SCANLINE = 261

    PALETTE = [
      124,124,124,    0,0,252,        0,0,188,        68,40,188,
      148,0,132,      168,0,32,       168,16,0,       136,20,0,
      80,48,0,        0,120,0,        0,104,0,        0,88,0,
      0,64,88,        0,0,0,          0,0,0,          0,0,0,
      188,188,188,    0,120,248,      0,88,248,       104,68,252,
      216,0,204,      228,0,88,       248,56,0,       228,92,16,
      172,124,0,      0,184,0,        0,168,0,        0,168,68,
      0,136,136,      0,0,0,          0,0,0,          0,0,0,
      248,248,248,    60,188,252,     104,136,252,    152,120,248,
      248,120,248,    248,88,152,     248,120,88,     252,160,68,
      248,184,0,      184,248,24,     88,216,84,      88,248,152,
      0,232,216,      120,120,120,    0,0,0,          0,0,0,
      252,252,252,    164,228,252,    184,184,248,    216,184,248,
      248,184,248,    248,164,192,    240,208,176,    252,224,168,
      248,216,120,    216,248,120,    184,248,184,    184,248,216,
      0,252,252,      248,216,248,    0,0,0,          0,0,0
    ]

    # initialize: Vram -> Ppu
    def initialize(vram)
      win = SDL2::Window.create("hongbai",
                                SDL2::Window::POS_CENTERED,
                                SDL2::Window::POS_CENTERED,
                                SCREEN_WIDTH, SCREEN_HEIGHT, 0)
      @renderer = win.create_renderer(-1, 0)
      @vram = vram
      @next_scanline_cycle = CYCLES_PER_SCANLINE
      @scanline = 0
      @x = 0
      @regs = Regs.new()
      @oam = Oam.new()
      @oam2 = Oam2.new()

      # A buffer that computes color priority and checks sprite 0 hit.
      @output = Output.new()

      # Upper left corner of the visiable area.
      @scroll_x = 0
      @scroll_y = 0

      @pattern_table = Matrix.build(512, 4, &:build_tile)
    end

    # step : Ppu -> Int -> [Bool, Bool]
    # The three bools are in order: vblank_nmi, scanline_irq
    def step(cpu_cycle_count)
      vblank_nmi, scanline_irq = false, false

      if cpu_cycle_count >= @next_scanline_cycle
        if @scanline < SCREEN_HEIGHT
          render_scanline
        end

        @scanline += 1

        scanline_irq = scanline_irq?

        if @scanline == VBLANK_SCANLINE
          set_vblank_start
          vblank_nmi = vblank_nmi?
        elsif @scanline == LAST_SCANLINE
          set_vblank_end
          @renderer.present
          @scanline = 0
        end

        @next_scanline_cycle += CYCLES_PER_SCANLINE
      end

      return vblank_nmi, scanline_irq
    end

    private
      # Ppu -> Integer -> Integer -> Tile
      def build_tile(row, col)
        # The pattern table lays in the VRAM from $0000 to $1fff,
        # including 512 tiles, each of 16 bytes, devided into two
        # 8 bytes planes.
        plane0 = Array.new(8) { |i| @vram.load(row * 16 + i) }
        plane1 = Array.new(8) { |i| @vram.load(row * 16 + 8 + i) }
        # make either plane a 8*8 matrix of bit
        plane0 = Matrix.build(8) { |r, c| (plane0[r] >> (7 - c)) & 1 }
        plane1 = Matrix.build(8) { |r, c| (plane1[r] >> (7 - c)) & 1 }
        # plane0 controls the 0 bit of color index,
        # plane1 controls the 1 bit whild the attribute controls the higher 2 bits
        tile = plane0 + plane1 * Matrix.scalar(8, 2)
        attribute = col << 2
        tile.map do |i| 
          if i.zero? # transparent point
            nil
          else
            index = (i | attribute) & 0x3f
            r, g, b = get_color(index)
            Color.new(r, g, b)
          end
        end
      end

      # Ppu -> Bool
      def scanline_irq?
        # TODO
      end

      # Ppu -> Bool
      def vblank_nmi?
        # TODO
      end

      # Ppu -> Nil
      def render_scanline
        @backdrop = get_backdrop_color
        # evaluate sprite info for next scanline
        sprite_evaluation
        # compute which nametable we are in
        nametable = nametable_base
        # nametable y index
        y_idx = ((@scroll_y + @scanline) % SCREEN_HEIGHT) / 8
        # 32 tiles (256 pixels) a scanline, every two tiles use a same palette attribute
        while @x < SCREEN_WIDTH
          # nametable x index
          x_idx = ((@scroll_x + @x) % SCREEN_WIDTH) / 8
          attribute = get_attribute(nametable, x_idx, y_idx)
          render_tile(nametable, x_idx, y_idx, attribute)
          render_tile(nametable, x_idx + 1, y_idx, attribute)
        end

        # HBlank
        # fetch sprite tiles for the next scanline
        sprite_fetch
        @x = 0
      end

      # Ppu -> [Integer, Integer, Integer]
      def get_color(index)
        r = PALETTE[index * 3 + 2]
        g = PALETTE[index * 3 + 1]
        b = PALETTE[index * 3 + 0]
        return r, g, b
      end

      # Ppu -> BDColor
      def get_backdrop_color
        # VRAM $3F00 stores the universal background color
        index = @vram.load(0x3f00) & 0x3f
        r, g, b = get_color(index)
        BDColor.new(r, g, b)
      end

      # Render a tile. (Only the current scanline)
      # Ppu -> nil
      def render_tile(nametable_base, x_idx, y_idx, attribute)
        tile_num = @vram.load(nametable_base + y_idx * 32 + x_idx)
        # TODO: Any need to process pattern 0 specially?
        pattern = @pattern_table[@regs.bg_pattern_table_addr + tile_num, attribute]

        if @regs.show_background?
          bg_colors = pattern.row((@scroll_y + @scanline) % 8)
          if @regs.show_sprites?
            # push_bg returns true when sprite 0 hits.
            if @output.push_bg(bg_colors, @x)
              @regs.set_sprite_zero_hit(true)
            end
            8.times {|i| put_pixel(@output[@x + i]) }
          else
            # Sprite rendering is disabled.
            bg_colors.each {|c| put_pixel(c) }
          end
        elsif @regs.show_sprites?
          # Background rendering is disabled.
          8.times {|i| put_pixel(@output[@x + i]) }
        else
          # Both background and pixel rendering are disabled.
          8.times { put_pixel(@backdrop) }
        end

        @x += 8
      end
 
      # Ppu -> Integer -> Integer -> Integer -> Integer
      def get_attribute(nametable_base, x_idx, y_idx)
        # load the attribute
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
        offset = y_idx / 4 * 8 + x_idx / 4
        attr_byte = @vram.load(nametable_base + 0x3c0 + offset)
        # Every 2 bits of an arttribute byte controls a 2*2 corner of the group of
        # 4*4 tiles
        #
        # 7654 3210
        # |||| ||++- topleft corner
        # |||| ++--- topright corner
        # ||++ ----- bottomleft corner
        # ++-- ----- bottomright corner
        if y_idx % 4 < 2
          if x_idx % 4 < 2 # topleft
            attr_byte & 3
          else # topright
            (attr_byte >> 2) & 3
          end
        else
          if x_idx % 4 < 2 # bottomleft
            (attr_byte >> 4) & 3
          else # topright
            (attr_byte >> 6) & 3
          end
        end
      end

      # Ppu -> Integer
      def nametable_base
        # There are four nametables in VRAM, each consists of 32*30 entrys.
        # Each entry presents an 8*8 pixels area on the screen. 
        #  -------------------------------- 
        # |$2000          |$2400           |
        # |               |                |
        # |            30 |                |
        # |               |                |
        # |       32      |       32       |
        # |--------------------------------|
        # |$2800          |$2C00           |
        # |               |                |
        # |            30 |                |
        # |               |                |
        # |               |                |
        #  --------------------------------
        #
        if @scroll_y % 480 < 240
          if @scroll_x % 512 < 256
            0x2000
          else
            0x2400
          end
        else
          if @scroll_x % 512 < 256
            0x2800
          else
            0x2c00
          end
        end
      end

      # Ppu -> nil
      def sprite_evaluation
        @oam2.init
        n = 0
        loop do
          y = @oam[n * 4]
          @oam2.insert(y)
          if sprite_on_next_scanline(y)
            (1..3).each { |i| @oam2.push(@oam[n * 4 + i]) }
          end
          n += 1
          return if n == 64

          break if @oam2.full?
        end

        m = 0
        while n < 64
          y = @oam[n * 4 + m]
          if sprite_on_next_scanline(y)
            @regs.set_sprite_overflow
            break
          else
            n += 1
            # the sprite overflow bug
            m = (m + 1) % 4
          end
        end
      end

      # Ppu -> Integer -> Bool
      def sprite_on_next_scanline(sprite_y_offset)
        sprite_y_offset <= @scanline + 1 &&
          sprite_y_offset + @regs.sprite_height >= @scanline + 1
      end

      # Ppu -> nil
      def sprite_fetch
        # TODO
      end

      # Ppu -> Integer -> nil
      def put_pixel(color)
        color ||= @backdrop
        @renderer.draw_color = [color.r, color.g, color.b]
        @renderer.draw_point(@x, @scanline)
      end

      # Ppu -> Nil
      def set_vblank_start
        @regs.set_in_vblank(true)
      end

      # Ppu -> Nil
      def set_vblank_end
        @regs.set_in_vblank(false)
        @regs.set_sprite_zero_hit(false)
        @regs.set_sprite_overflow(false)
      end
  end

  class Regs
    # Regs -> Bool -> Nil
    def set_in_vblank(b)
        # TODO
    end

    # Regs -> Bool -> Nil
    def set_sprite_zero_hit(b)
        # TODO
    end

    # Regs -> Bool
    def show_background?
        # TODO
    end

    # Regs -> Bool
    def show_sprites?
        # TODO
    end

    # Regs -> Integer
    # return 0 or 0x1000
    def bg_pattern_table_addr
    end

    # Regs -> Integer
    # return 8 or 16
    def sprite_height
    end
  end

  class Oam; end

  class Oam2
    def initialize
      @arr = Array.new(8 * 4, 0xff)
      @cursor = 0
      @openslot = 0
      @push_count = 0
    end

    def init
      @arr.map! { 0xff }
      @cursor = 0
      @openslot = 0
      @push_count = 0
    end

    def push(n)
      @arr[@cursor] = n
      @cursor += 1
      @openslot = @cursor
      @push_count += 1
    end

    def insert(n)
      @arr[@openslot] = n
      @cursor = @openslot + 1
    end

    def full?
      @push_count >= 24 # 8 sprites, each 3 pushes
    end
  end

  class Vram
  end

  class Color < Struct.new(:r, :g, :b); end

  # A tile is a 8*8 Matrix of Color
  class Tile < Matrix; end

  class OutputItem < Struct.new(:color, :from_sprite_0, :above_bg); end

  class Output
    def initialize
      @may_hit_sprite_0 = false
      @items = Array.new(256) { OutputItem.new }
    end

    attr_accessor :may_hit_sprite_0

    def clear
      @may_hit_sprite_0 = false
      @items.each do |i|
        i.color = nil
        i.from_sprite_0 = nil
        i.above_bg = nil
      end
    end

    def [](n)
      @items[n].color
    end

    # Output -> Array<Color> -> Integer -> Bool -> Bool -> Nil
    # where colors.ength == 8
    # x_offset >= 0; <= 247
    def push_sprite(colors, x_offset, from_sprite_0, above_bg)
      i = x_offset
      colors.each do |c|
        if @items[i].above_bg.nil?
          # No sprite on this dot 
          @tiems[i].color = c
          @items[i].from_sprite_0 = from_sprite_0
          @items[i].above_bg = above_bg
        end
        i += 1
      end
    end

    # Output -> Array<Color> -> Integer -> Bool
    # Return true if sprite 0 hits, return false otherwise.
    def push_bg(colors, x_offset)
      i = x_offset
      if @may_hit_sprite_0
        # Only checks when sprite 0 is included in this render
        hit = false
        colors.each do |c|
          item = @items[i]
          if item.from_sprite_0 && !item.color.nil? && !c.nil?
            hit = true
          end
          push_bg_color(c, i)
          i += 1
        end
        hit
      else
        colors.each do |c|
          push_bg_color(c, i)
          i += 1
        end
        false
      end
    end

    private
      # Output -> Color -> Integer -> Nil
      # Insert a background color at the index
      def push_bg_color(color, index)
        item = @items[index]
        unless !item.color.nil? && item.above_bg
          @items[index].color = color
        end
      end
  end
end

#
#      SDL2.init(SDL2::INIT_TIMER |
#                SDL2::INIT_AUDIO |
#                SDL2::INIT_VIDEO |
#                SDL2::INIT_EVENTS)

#references:
#https://courses.cit.cornell.edu/ee476/FinalProjects/s2009/bhp7_teg25/bhp7_teg25/
#http://everything2.com/index.pl?node_id=925418
#http://nesdev.com/NESDoc.pdf
