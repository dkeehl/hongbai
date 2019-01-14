require_relative './sdl/video'
require_relative './ppu_address'

module Hongbai
  SCREEN_WIDTH = 256
  SCREEN_HEIGHT = 240

  # TODO:
  # ** Color emphasize
  # ** Describe ppu address increment in a more concise way.
 
  class Ppu
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
   
    VRAM_ADDR_INC = [1, 32]

    def initialize(rom, driver, context)
      @context = context
      @renderer = driver
      palette = Palette.new
      @vram = Vram.new(rom, palette)
      @oam = Oam.new
      @oam2 = Oam2.new
      # A buffer that computes color priority and checks sprite 0 hit.
      @sprite_buffer = Output.new
      @bg_buffer = Array.new(8 * 2, 0)
      
      # Rendering latches
      @tile_num = 0xff
      @attribute = 0
      @tile_bitmap_low = 0

      # Registers
      # PPU_CTRL
      @vram_addr_increment = 1
      @sprite_pattern_table_addr = 0
      @bg_pattern_table_addr = 0
      @sprite_8x16_mode = false
      @sprite_height = 8
      @generate_vblank_nmi = false
      # PPU_MASK
      @color_functions = [palette.inner, palette.method(:grey_scale)]
      @color_function = @color_functions[0]
      @render_functions =               # sprite(1: enable) background(1: enable)
        [method(:render_none),          # 00
         method(:render_bg),            # 01
         method(:render_sprite),        # 10
         method(:render_bg_and_sprite)] # 11
      @render_type = 0
      @render_function = @render_functions[@render_type]
      @left_most_render_function = @render_function
      @rendering_enabled = false
      @emphasize_red = false
      @emphasize_green = false
      @emphasize_blue = false
      # PPU_STATUS
      @ppu_status = 0
      @in_vblank = false
      # PPU_ADDR & PPU_SCROLL
      @ppu_addr = Address.new
      @tmp_addr = TempAddress.new
      @fine_x_offset = 0
      @toggle = false
      @ppu_data_read_buffer = 0

      @pattern_table = rom.pattern_table

      @output = Array.new(SCREEN_WIDTH * SCREEN_HEIGHT, 0xffffffff)
      @output_offset = 0
      @scanline = 0
      @x = 0

      @main_loop = Fiber.new { run_main_loop }
      @even_frame = true

      # debug
      @trace = false
    end

    attr_reader :main_loop
    attr_writer :trace

    def run_main_loop
      while true do
        # scanline 0 to 239, the visible scanlines
         
        # scanline 0
        # cycle 0 is skipped on odd cycles when rendering is enabled
        Fiber.yield if @even_frame || !@rendering_enabled
        visible_scanline
        @scanline += 1
        1.step(239) do
          # cycle 0, idle
          Fiber.yield
          visible_scanline
          @scanline += 1
        end

        # scanline 240
        idle_scanline

        # scanline 241
        vblank_scanline

        # scanline 242 to 260
        242.step(260) { idle_scanline }

        # pre-render line
        @renderer.display @output
        @output_offset = 0
        @scanline = 0
        @even_frame = !@even_frame
        @context.on_new_frame
        pre_render_scanline
      end
    end

    def read_oam_data(_addr)
      @oam.read
    end

    def read_ppu_status(_addr)
      @toggle = false
      ret = @ppu_status
      @ppu_status &= 0x7f # clear the vblank flag
      ret
    end

    def read_ppu_data(_addr)
      # TODO: I'd like to move the increment logic into Addr class, thus I can write:
      # addr = @ppu_addr.val
      # @ppu_addr.load_next_value
      if @rendering_enabled
        addr = @ppu_addr.tile
        @ppu_addr.coarse_x_increment
        @ppu_addr.y_increment
      else
        # Mirror down addresses greater than 0x3fff
        addr = @ppu_addr.to_i & 0x3fff
        @ppu_addr.add @vram_addr_increment
      end
      val = @vram.read(addr)
      buffered = @ppu_data_read_buffer
      @ppu_data_read_buffer = val

      addr < 0x3f00 ? buffered : val
    end

    def write_ppu_ctrl(_addr, val)
      @tmp_addr.nametable_x      = val[0]
      @tmp_addr.nametable_y      = val[1]
      @vram_addr_increment       = VRAM_ADDR_INC[val[2]]
      @sprite_pattern_table_addr = val[3] * 2048 # 256 tiles * 8 rows per tile
      @bg_pattern_table_addr     = val[4] * 2048

      @sprite_8x16_mode = val[5] == 1
      @sprite_height = @sprite_8x16_mode ? 16 : 8

      vblank_orig = @generate_vblank_nmi
      @generate_vblank_nmi = val[7] == 1
      if !vblank_orig && @generate_vblank_nmi && @ppu_status[7] == 1
        @context.nmi = true
      end
    end

    def write_ppu_mask(_addr, val)
      @emphasize_red          = val[5] == 1
      @emphasize_green        = val[6] == 1
      @emphasize_blue         = val[7] == 1

      @color_function = @color_functions[val[0]]
      @render_type = (val >> 3) & 3
      @render_function = @render_functions[@render_type]
      @left_most_render_function = @render_functions[(val >> 1) & @render_type]
      @rendering_enabled = @render_type != 0 && !@in_vblank
    end

    def write_oam_addr(_addr, val)
      @oam.addr = val
    end

    def write_oam_data(_addr, val)
      @oam.write val
    end

    def write_ppu_scroll(_addr, val)
      if @toggle # toggle is true, the second write
        @tmp_addr.fine_y_offset = val & 7
        @tmp_addr.coarse_y_offset = val >> 3
      else
        @fine_x_offset = val & 7
        @tmp_addr.coarse_x_offset = val >> 3
      end
      @toggle = !@toggle
    end

    def write_ppu_addr(_addr, val)
      if @toggle
        @tmp_addr.update_lo val
        @ppu_addr.copy @tmp_addr
      else
        @tmp_addr.update_hi val
      end
      @toggle = !@toggle
    end

    def write_ppu_data(_addr, val)
      if @rendering_enabled
        addr = @ppu_addr.tile
        @vram.write(addr, val)
        # TODO: If coincide with a standard VRAM address increment,
        # don't increase the relevant counter.
        @ppu_addr.coarse_x_increment
        @ppu_addr.y_increment
      else
        # Mirror down addresses greater than 0x3fff
        addr = @ppu_addr.to_i & 0x3fff
        @vram.write(addr, val)
        @ppu_addr.add @vram_addr_increment
      end
    end

    private
      def idle_scanline
        0.step(340) { Fiber.yield }
      end

      def vblank_scanline
        Fiber.yield
        set_vblank_start
        @context.nmi = @generate_vblank_nmi
        1.step(340) { Fiber.yield }
      end

      def pre_render_scanline
        # cycle 0, idle
        Fiber.yield
        # cycle 1
        set_vblank_end
        1.step(255) { Fiber.yield }
        # cycle 256
        @ppu_addr.y_increment if @rendering_enabled
        Fiber.yield
        # cycle 257
        @ppu_addr.copy_x @tmp_addr if @rendering_enabled
        Fiber.yield

        258.step(279) { Fiber.yield }
        # cycle 280-304
        280.step(304) do
          @ppu_addr.copy_y @tmp_addr if @rendering_enabled
          Fiber.yield
        end

        305.step(320) { Fiber.yield }
        321.step(336, 8) do 
          tile_fetch_8_cycles { @bg_buffer.shift }
        end
        scanline_cycle_337_to_340
      end

      def visible_scanline
        # last 340 cycles of 341 cycles in total
        @x = 0
        # cycle 1-8
        tile_fetch_8_cycles { draw_point @left_most_render_function[] }
        # cycle 9-64
        9.step(64, 8) do
          tile_fetch_8_cycles { draw_point @render_function[] }
        end
        # In fact this happens during cycle 1-64
        @oam2.init
        # cycle 65-256, with sprite evaluation
        65.step(256, 8) do
          tile_fetch_8_cycles { draw_point @render_function[] }
        end
        # still in cycle 256
        # FIXME: should yield here
        sprite_evaluation
        @ppu_addr.y_increment if @rendering_enabled
        # cycle 257-320, fetch sprite tiles for the next scanline
        scanline_cycle_257_to_320
        sprite_fetch
        # cycle 321-336, fetch the first two tiles for the next scanline
        321.step(336, 8) do 
          tile_fetch_8_cycles { @bg_buffer.shift }
        end
        # cycle 337-340
        #read_nametable_byte
        #read_nametable_byte
        scanline_cycle_337_to_340
      end

      def tile_fetch_8_cycles
        # cycle 1
        yield
        Fiber.yield
        # cycle 2
        yield
        read_nametable_byte
        Fiber.yield
        # cycle 3
        yield
        Fiber.yield
        # cycle 4
        yield
        read_attr_byte
        Fiber.yield
        # cycle 5
        yield
        Fiber.yield
        # cycle 6
        yield
        get_tile_low
        Fiber.yield
        # cycle 7
        yield
        Fiber.yield
        # cycle 8
        yield
        get_tile_high
        reload_shift_register
        @ppu_addr.coarse_x_increment if @rendering_enabled
        Fiber.yield
      end

      def scanline_cycle_257_to_320
        @ppu_addr.copy_x @tmp_addr if @rendering_enabled
        257.step(320, 8) do
          # cycle 1
          #read_sprite_y_pos
          Fiber.yield
          # cycle 2
          #read_sprite_tile_num
          Fiber.yield
          # cycle 3
          #read_sprite_x_pos # 1 cycle
          Fiber.yield
          # cycle 4
          #read_sprite_attr  # 1 cycle
          Fiber.yield
          # cycle 5
          Fiber.yield
          # cycle 6
          #get_tile_low
          Fiber.yield
          # cycle 7
          Fiber.yield
          # cycle 8
          #get_tile_high
          #buffer_sprite
          Fiber.yield
        end
      end

      def scanline_cycle_337_to_340
        337.step(340) { Fiber.yield }
      end

      def read_nametable_byte
        @tile_num = @vram.read(@ppu_addr.tile)
      end

      def get_tile_low
        # Not really do a memory fetch, just determine the address of the pattern
        @pattern_addr = @bg_pattern_table_addr + @tile_num * 8 + @ppu_addr.fine_y_offset
      end

      def get_tile_high
        @pattern = @pattern_table[@pattern_addr][@attribute]
      end

      def reload_shift_register
        @bg_buffer[8, 8] = @pattern
      end

      def draw_point(color_index)
        @output[@output_offset] = PALETTE[@color_function[color_index]]
        @output_offset += 1
        @bg_buffer.shift
        @x += 1
      end

      def render_bg_and_sprite
        bg_color = @bg_buffer[@fine_x_offset]
        if @sprite_buffer.push_point(bg_color, @x)
          set_sprite_zero_hit
        end
        @sprite_buffer[@x]
      end

      def render_bg
        @bg_buffer[@fine_x_offset]
      end

      def render_sprite
        @sprite_buffer[@x]
      end

      # TODO: if the ppu address is pointing to the pallete, return the color
      def render_none; 0 end

      # Pre-compute attributes for every address in a nametable
      # with all 256 possible atribute bytes.
      #
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
      ATTR_TABLE = (0..0xff).map do |val|
        (0..0x3ff).map do |pos|
          y, x = pos.divmod(32)
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

      def read_attr_byte
        byte = @vram.read(@ppu_addr.attribute)
        @attribute = ATTR_TABLE[byte][@ppu_addr.to_i & 0x3ff]
      end

      # Ppu -> nil
      def sprite_evaluation
        # TODO: use OAMADDR to start
        y = @oam[0]
        @oam2.insert(y)
        if sprite_on_scanline(y)
          1.step(3) { |i| @oam2.push(@oam[i]) }
          @oam2.has_sprite_zero = true
        end

        n = 1
        loop do
          y = @oam[n * 4]
          @oam2.insert(y)
          if sprite_on_scanline(y)
            1.step(3) { |i| @oam2.push(@oam[n * 4 + i]) }
          end
          n += 1
          return if n == 64

          break if @oam2.full?
        end

        m = 0
        while n < 64
          y = @oam[n * 4 + m]
          if sprite_on_scanline(y)
            set_sprite_overflow
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
        @sprite_buffer.clear

        @oam2.each_sprite do |tile, attr, flip_h, flip_v, x, y, prior, sprite0|
          y_inter = @scanline - y
          if !@sprite_8x16_mode
            # 8*8 sprite mode
            tile += @sprite_pattern_table_addr
            y_inter = 7 - y_inter if flip_v
          else
            # 8*16 sprite mode
            tile = Ppu.to_8x16_sprite_tile_addr(tile)
            y_inter = 15 - y_inter if flip_v
          end

          colors = @pattern_table[tile * 8 + y_inter][attr]
          colors = colors.reverse if flip_h
          @sprite_buffer.push_sprite(colors, x, prior, sprite0)
        end
      end

      # Integer -> Integer
      def self.to_8x16_sprite_tile_addr(tile_number)
        bank = tile_number & 1 * 256
        bank + (tile_number & 0xfe)
      end

      def set_sprite_zero_hit
        @ppu_status |= 0x40
      end

      def set_sprite_overflow
        @ppu_status |= 0x20
      end

      def set_vblank_start
        # set_in_vblank to 1
        @ppu_status |= 0x80
        @in_vblank = true
        @rendering_enabled = false
      end

      # Ppu -> Nil
      def set_vblank_end
        # set in vblank to 0
        @ppu_status &= 0x7f
        @in_vblank = false
        @rendering_enabled = @render_type != 0
        # clear sprite_zero_hit flag
        @ppu_status &= 0xbf
        # clear sprite overflow flag
        @ppu_status &= 0xdf
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
        prior = attributes[5] == 0
        flip_h = attributes[6] == 1
        flip_v = attributes[7] == 1
        return tile, attr, flip_h, flip_v, x, y, prior
      end
  end

  class Vram
    def initialize(rom, palette)
      @rom = rom
      @palette = palette

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
        @read_map[i] = @palette.method(:read)
        @write_map[i] = @palette.write_method(i)
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
      @items = Array.new(SCREEN_WIDTH) { Item.new(0, nil, nil) }
    end

    attr_accessor :may_hit_sprite_0

    def clear
      0.step(255) do |n|
        i = @items[n]
        i.color = 0 
        i.from_sprite_0 = nil
        i.above_bg = nil
      end
    end

    # Output -> Integer -> ColorIndex
    def [](n)
      @items[n].color
    end

    def push_sprite(pattern, x_offset, above_bg, from_sprite_0)
      i = x_offset
      0.step(7) do |n|
        c = pattern[n]
        item = @items[i]
        if item && (item.color == 0 || (above_bg && !item.above_bg))
          item.color = c
          item.from_sprite_0 = from_sprite_0
          item.above_bg = above_bg
        end
        i += 1
      end
    end

    def push_point(color, x_offset)
      item = @items[x_offset]
      hit = item.from_sprite_0 && color != 0 && item.color != 0 && x_offset != 255
      item.color = color unless item.color != 0 && item.above_bg || color == 0
      hit
    end
  end

  class Palette
    MIRRORS = [0x00, 0x04, 0x08, 0x0c, 0x10, 0x14, 0x18, 0x1c] 

    def initialize
      # runs from $3f00 to $3f1f, 32 bytes
      @inner = Array.new(32, 0x3f)
    end

    attr_reader :inner

    def grey_scale(i)
      @inner[i] & 0x30
    end

    def read(addr)
      @inner[addr & 0x1f]
    end

    def write(addr, val)
      @inner[addr & 0x1f] = val & 0x3f
    end

    def write_mirror(addr, val)
      @inner[addr & 0xf] = val & 0x3f
      @inner[addr & 0xf + 0x10] = val & 0x3f
    end

    def write_method(i)
      MIRRORS.include?(i & 0x1f) ? method(:write_mirror) : method(:write)
    end
  end
end
