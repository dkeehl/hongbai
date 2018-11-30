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
      @regs = Regs.new()
      @oam = Oam.new()
      @oam2 = Oam2.new()

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
        attribute = Matrix.build(8) { col }
        # plane0 controls the 0 bit of color index,
        # plane1 controls the 1 bit whild the attribute controls the higher 2 bits
        tile = plane0 + plane1 * Matrix.scalar(8, 2) + attribute * Matrix.scalar(8, 4)
        tile.map do |i| 
          r, g, b = get_color(i & 0x3f)
          Color.new(r, g, b)
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
        backdrop = get_backdrop_color

        (0...SCREEN_WIDTH).each do |x|
          background = get_background_pixel(x)
          sprite_color = get_sprite_pixel(x, background)
          color = sprite_color | background | backdrop
          put_pixel(x, color)
        end
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

      # Ppu -> Integer -> nil | BGColor
      def get_background_pixel(x)
        return unless @regs.show_background?
        x = x + @scroll_x
        y = @scanline + @scroll_y

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
        # Ench entry points to a tile, and is associated with a 2-bit attribute.
        # A tile is an 8*8 pixels pattern, having 4 dfferent colored varients
        # according to the 2-bit attribute.
        tile, attribute = fetch_nametable_entry(x, y)
        return if tile.zero?

        pattern = @pattern_table[@regs.bg_pattern_table_addr * 256 + tile, attribute]
        color = pattern[y % 8, x % 8]
        BGColor.new(color.r, color.g, color.b)
      end

      # Ppu -> Integer -> Integer -> (TileNumber, Arttribute)
      # where Arttibute is a 2-bit integer([0-3]).
      # and TileNumber is a byte.
      def fetch_nametable_entry(x, y)
        x_idx = x / 8 % 64
        y_idx = y / 8 % 60
        
        base = if y_idx < 30
                 if x_idx < 32
                   0x2000
                 else
                   0x2400
                 end
               else
                 if x_idx < 32
                   0x2800
                 else
                   0x2c00
                 end
               end
        x_idx %= 32
        y_idx %= 30

        tile = @vram.load(base + y_idx * 32 + x_idx)

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
        group = y_idx / 4 * 8 + x_idx / 4
        attr_byte = @vram.load(base + 0x3c0 + group)

        # Every 2 bits of an arttribute byte controls a 2*2 corner of the group of
        # 4*4 tiles
        #
        # 7654 3210
        # |||| ||++- topleft corner
        # |||| ++--- topright corner
        # ||++ ----- bottomleft corner
        # ++-- ----- bottomright corner
        x_idx %= 4
        y_idx %= 4
        attribute = if y_idx < 2
                      if x_idx < 2
                        attr_byte & 0x3 # top left
                      else
                        (attr_byte >> 2) & 0x3 # top right
                      end
                    else
                      if x_idx < 2
                        (attr_byte >> 4) & 0x3 # bottom left
                      else
                        (attr_byte >> 6) & 0x3 # bottom right
                      end
                    end
        return tile, attribute
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

      # Ppu -> Bool
      def sprite_on_next_scanline(y)
        y <= @scanline + 1 && y + 7 >= @scanline + 1
      end

      # Ppu -> nil
      def sprite_fetch
        # TODO
      end

      # Ppu -> Integer -> nil | BGColor -> nil | SpriteColorAbove | SpriteColorBelow
      def get_sprite_pixel(x, background)
        # draw sprites data in oam2
        # TODO
        # evaluate sprite info for next scanline
        sprite_evaluation
        sprite_fetch
      end

      # Ppu -> Integer -> nil
      def put_pixel(x, color)
        @renderer.draw_color = [color.r, color.g, color.b]
        @renderer.draw_point(x, @scanline)
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

  class BDColor < Struct.new(:r, :g, :b)
    # Color -> Color -> Color
    # Backdrop color, has a priority lower than any other colors except nil
    def |(other)
      other.nil? ? self : other
    end
  end

  class SpriteColorBelow < BDColor
    # Color -> Color -> Color
    def |(other)
      case other
      when BGColor then other
      else self
      end
    end
  end

  class BGColor < SpriteColorBelow
    def |(other)
      case other
      when SpriteColorAbove then other
      else self
      end
    end
  end

  class SpriteColorAbove < BGColor
    def |(other)
      self
    end
  end

  class Color < Struct.new(:r, :g, :b); end

  # A tile is a 8*8 Matrix of Color
  class Tile < Matrix; end
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
