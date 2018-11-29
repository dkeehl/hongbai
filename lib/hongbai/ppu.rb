require 'sdl2'

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

      # Upper left corner of the visiable area.
      @scroll_x = 0
      @scroll_y = 0
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
        visible_sprites = compute_visible_sprites

        (0...SCREEN_WIDTH).each do |x|
          background = get_background_pixel(x)
          sprite_color = get_sprite_pixel(visible_sprites, x, background)
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

        # Translate the tile number into a VRAM address
        #
        # DCBA98 76543210
        # ---------------
        # OHRRRR CCCCPTTT
        # |||||| |||||+++- T: Fine Y offset, the row number within a tile
        # |||||| ||||+---- P: Bit plane (0: "lower"; 1: "upper")
        # |||||| ++++----- C: Tile column
        # ||++++ --------- R: Tile row
        # |+---- --------- H: Sprite table half (0; "left"; 1: "right")
        # +----- --------- O: Pattern table address (0: $0000-$0fff; 1: $1000-$1fff)
        #
        addr = (tile << 4) | (y % 8) | @regs.background_pattern_table_addr
        #            +          +           +
        #           R C         T           O
        plane0 = @vram.load(addr)
        plane1 = @vram.load(addr + 8)
        bit0 = (plane0 >> (7 - (x % 8))) & 1
        bit1 = (plane1 >> (7 - (x % 8))) & 1

        color_offset = (attribute << 2) | (bit1 << 1) | bit0
        index = @vram.load(0x3f00 + color_offset) & 0x3f
        r, g, b = get_color(index)
        BGColor.new(r, g, b)
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

      # Ppu -> nil | Array<Integer>
      # where Array's length <= 8
      def compute_visible_sprites
        return unless @regs.show_sprites?
        # TODO
      end

      # Ppu -> nil | Array<Integer> -> nil | BGColor ->
      # nil | SpriteColorAbove | SpriteColorBelow
      def get_sprite_pixel(sprites, background)
        return if sprites.nil?
        # TODO
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

  #class Oam
  #end

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
