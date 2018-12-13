require 'sdl2'
require 'matrix'

module Hongbai
  SCREEN_WIDTH = 256
  SCREEN_HEIGHT = 240

  # TODO:
  # ** Odd and even frames
  # ** Leftmost pixles render control
  # ** Color emphasize and grey scale display
 
  class Ppu
    # A scanline is 341 ppu clocks
    # Ppu runs at 3 times the cpu clock rate
    CYCLES_PER_SCANLINE = 114 
    VBLANK_SCANLINE = 241
    LAST_SCANLINE = 261

    # initialize: Rom -> Ppu
    def initialize(rom, win)
      @renderer = win.create_renderer(-1, 0)
      @vram = Vram.new(rom)
      @next_scanline_cycle = CYCLES_PER_SCANLINE
      @scanline = 0
      @frame = 0
      @x = 0
      @regs = Regs.new
      @oam = Oam.new
      @oam2 = Oam2.new

      # A buffer that computes color priority and checks sprite 0 hit.
      @buffer = Output.new

      # Upper left corner of the visiable area in current nametable
      @scroll_x = 0
      @scroll_y = 0

      # TODO: This is a hack to speed up. But it doesn't work with all mappers
      @pattern_table = Matrix.build(512, 8) {|row, col| build_tile(row, col) }

      @trace = false
    end

    attr_reader :frame, :scanline

    # step : Ppu -> Int -> [Bool, Bool]
    # The three bools are in order: vblank_nmi, scanline_irq
    def step(cpu_cycle_count)
      vblank_nmi, scanline_irq = false, false

      if @scanline == 176 &&
          (@frame > 30 && @frame < 40 || @frame > 510 && @frame < 530)
        @trace = true
      end

      @sprite_height ||= @regs.sprite_height_mode

      while @next_scanline_cycle < cpu_cycle_count
        if @scanline < SCREEN_HEIGHT
          render_scanline
        end

        @scanline += 1

        scanline_irq = @vram.rom.next_scanline_irq

        if @scanline == VBLANK_SCANLINE
          set_vblank_start
          vblank_nmi = @regs.generate_vblank_nmi?
        elsif @scanline == LAST_SCANLINE
          set_vblank_end
          @renderer.present
          @scanline = 0
          @frame += 1
        end

        @next_scanline_cycle += CYCLES_PER_SCANLINE
      end

      @trace = false
      return vblank_nmi, scanline_irq
    end

    # Take a Cpu memory space address, return the corresponding register value
    def load(addr)
      case addr & 7
      when 0 then @regs.ppu_ctrl
      when 1 then @regs.ppu_mask
      when 2 then read_ppu_status
      when 3 then 0 # write only
      when 4 then @oam[@regs.oam_addr]
      when 5 then 0 # write only
      when 6 then 0 # write only
      when 7 then read_ppu_data
      else raise "Unreachable case"
      end
    end

    # Take a Cpu memory space address, update a register
    def store(addr, val)
      case addr & 7
      when 0 then @regs.ppu_ctrl = val
      when 1 then @regs.ppu_mask = val
      when 2 then nil # read only
      when 3 then @regs.oam_addr = val
      when 4 then write_oam_data(val)
      when 5 then update_ppu_scroll(val)
      when 6 then update_ppu_addr(val)
      when 7 then write_ppu_data(val)
      else raise "Unreachable case"
      end
    end

    # Ppu -> Integer -> Nil
    # Public for OAM DMA
    def write_oam_data(val)
      @oam[@regs.oam_addr] = val
      @regs.oam_addr = (@regs.oam_addr + 1) & 0xff
    end

    private
      # Ppu -> Integer
      def read_ppu_status
        @regs.reset_toggle
        @regs.ppu_status
      end

      # Ppu -> Integer -> Nil
      def update_ppu_scroll(val)
        if @regs.toggle? # toggle is true, the second write
          @scroll_y = val
        else
          @scroll_x = val
        end
        @regs.toggle!
      end

      # Ppu -> Integer -> Nil
      def update_ppu_addr(val)
        if @regs.toggle?
          @regs.ppu_addr = @regs.ppu_addr & 0xff00 | val
        else
          @regs.ppu_addr = @regs.ppu_addr & 0x00ff | (val << 8)
          # This is a hack
          nametable = (@regs.ppu_addr >> 10) & 3
          @regs.ppu_ctrl = @regs.ppu_ctrl & (0xfc | nametable)
        end
        @regs.toggle!
      end

      # Ppu -> Integer
      def read_ppu_data
        # Mirror down addresses greater than 0x3fff
        addr = @regs.ppu_addr & 0x3fff
        val = @vram.load(addr)
        @regs.ppu_addr += @regs.vram_addr_increment
        buffered = @regs.ppu_data_read_buffer
        @regs.ppu_data_read_buffer = val

        addr < 0x3f00 ? buffered : val
      end

      # Ppu -> Integer -> Nil
      def write_ppu_data(val)
        # Mirror down addresses greater than 0x3fff
        addr = @regs.ppu_addr & 0x3fff
        @vram.store(addr, val)
        @regs.ppu_addr += @regs.vram_addr_increment
      end

      # Ppu -> Integer -> Integer -> Tile
      # A Tile is a 8*8 Matrix of Color
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
        nametable = @regs.nametable_base

        tile_internal_y_offset = (@scroll_y  + @scanline) % 8
        tile_internal_x_offset = @scroll_x % 8

        unless tile_internal_x_offset.zero?
          first_tile = true
          first = (tile_internal_x_offset..7)
          last = (0...tile_internal_x_offset)
        end

        while @x < SCREEN_WIDTH
          attribute = get_attribute(nametable, x_idx, y_idx)
          tile_num = @vram.load(nametable + y_idx * 32 + x_idx)
          tile = @pattern_table[@regs.bg_pattern_table_addr * 256 + tile_num, attribute]
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
        if @regs.show_background?
          if @regs.show_sprites?
            # push_bg returns true when sprite 0 hits.
            if @buffer.push_bg(bg_colors, range, @x)
              @regs.set_sprite_zero_hit(true)
              #raise "frame #{@frame}, scanline #{@scanline}"
            end
            range.each { put_pixel(@buffer[@x]); @x += 1 }
          else
            # Sprite rendering is disabled.
            range.each {|i| put_pixel(bg_colors[i]); @x += 1 }
          end
        elsif @regs.show_sprites?
          # Background rendering is disabled.
          range.each { put_pixel(@buffer[@x]); @x += 1 }
        else
          # Both background and pixel rendering are disabled.
          range.each { put_pixel(0); @x += 1 }
        end
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

      # Ppu -> nil
      def sprite_evaluation
        @oam2.init

        # TODO: use OAMADDR to start
        y = @oam[0]
        @oam2.insert(y)
        if sprite_on_scanline(y)
          (1..3).each { |i| @oam2.push(@oam[i]) }
          @oam2.has_sprite_zero = true
        end

        n = 1
        loop do
          y = @oam[n * 4]
          @oam2.insert(y)
          if sprite_on_scanline(y)
            (1..3).each { |i| @oam2.push(@oam[n * 4 + i]) }
          end
          n += 1
          return if n == 64

          break if @oam2.full?
        end

        m = 0
        while n < 64
          y = @oam[n * 4 + m]
          if sprite_on_scanline(y)
            @regs.set_sprite_overflow(true)
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
          if @sprite_height == 8
            # 8*8 sprite mode
            tile += @regs.sprite_pattern_table_addr
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

      # Ppu -> Integer -> nil
      def put_pixel(color_index)
        color = @vram.palette.get_color(color_index)
        @renderer.draw_color = color
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
    def initialize
      @ppu_ctrl = 0
      @ppu_mask = 0
      @ppu_status = 0
      @oam_addr = 0
      @ppu_addr = 0

      # Indicates if a write is the second write to PPUSCROLL and PPUADDRESS
      @toggle = false
      @ppu_data_read_buffer = 0
    end

    attr_accessor :ppu_ctrl, :ppu_mask, :ppu_status, :oam_addr,
                  :ppu_addr, :ppu_data_read_buffer

    def toggle?; @toggle end

    def toggle!
      @toggle = !@toggle
    end

    def reset_toggle
      @toggle = false
    end

    # Regs -> Bool -> Nil
    def set_in_vblank(b)
      b ? @ppu_status |= 0x80 : @ppu_status &= 0x7f
    end

    # Regs -> Bool -> Nil
    def set_sprite_zero_hit(b)
      b ? @ppu_status |= 0x40 : @ppu_status &= 0xbf
    end

    # Regs -> Bool -> Nil
    def set_sprite_overflow(b)
      b ? @ppu_status |= 0x20 : @ppu_status &= 0xdf
    end

    # Regs -> Bool
    def show_background?
      ((@ppu_mask >> 3) & 1) == 1
    end

    # Regs -> Bool
    def show_sprites?
      ((@ppu_mask >> 4) & 1) == 1
    end

    # Regs -> Integer
    # return $2000 or $2400 or $2800 or $2c00
    def nametable_base
      (@ppu_ctrl & 3) * 0x400 + 0x2000
    end

    def vram_addr_increment
      ((@ppu_ctrl >> 2) & 1).zero? ? 1 : 32
    end

    # Regs -> Integer
    # return 0 or 0x1000
    def sprite_pattern_table_addr
      ((@ppu_ctrl >> 3) & 1) * 0x1000
    end

    # Regs -> Integer
    # return 0 or 1
    def bg_pattern_table_addr
      (@ppu_ctrl >> 4) & 1
    end

    # Regs -> Integer
    # return 8 or 16
    def sprite_height_mode
      ((@ppu_ctrl >> 5) & 1) * 8 + 8
    end

    # Regs -> Bool
    def generate_vblank_nmi?
      ((@ppu_ctrl >> 7) & 1) == 1
    end
  end

  class Oam
    def initialize
      @arr = Array.new(256, 0)
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
    # Memory map
    # $0000 - $1fff pattern table (rom)
    # $2000 - $2fff 4 nametables
    # $3000 - $3eff mirrors of $2000 - $2eff
    # $3f00 - $3f1f palette
    # $3f20 - $3fff mirrors of $3f00 - $3f1f
    def initialize(rom)
      @rom = rom
      @ram = Array.new(0x800, 0)
      @palette = Palette.new
    end

    attr_reader :palette, :rom

    def load(addr)
      if addr < 0x2000
        @rom.chr_load(addr)
      elsif addr < 0x3f00
        addr = @rom.mirroring.mirror(addr & 0xfff)
        @ram[addr]
      elsif addr < 0x4000
        addr &= 0x1f
        @palette.load(addr)
      else
        raise "Unreachable vram address #{addr}"
      end
    end

    def store(addr, val)
      if addr < 0x2000
        @rom.chr_store(addr, val)
      elsif addr < 0x3f00
        addr = @rom.mirroring.mirror(addr & 0xfff)
        @ram[addr] = val
      elsif addr < 0x4000
        addr &= 0x1f
        @palette.store(addr, val)
      else
        raise "Unreachable vram address #{addr}"
      end
    end
  end

  class Output
    class Item < Struct.new(:color, :from_sprite_0, :above_bg); end

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
    
    class Item < Struct.new(:val, :color); end

    def self.get_color(index)
      b = PALETTE[index * 3 + 2]
      g = PALETTE[index * 3 + 1]
      r = PALETTE[index * 3 + 0]
      return r, g, b
    end

    def initialize
      # rus from $3f00 to $3f1f, 32 bytes
      @items = Array.new(32) { Item.new(0, [0, 0, 0]) }
      # Mirroring
      [0x10, 0x14, 0x18, 0x1c].each do |addr|
        @items[addr] = @items[addr - 0x10]
      end
    end

    def get_color(color_index)
      @items[color_index].color
    end

    def load(addr)
      @items[addr].val
    end

    def store(addr, val)
      item = @items[addr]
      r, g, b = Palette.get_color(val & 0x3f)
      item.val = val
      item.color[0] = r
      item.color[1] = g
      item.color[2] = b
    end
  end
end

#references:
#https://courses.cit.cornell.edu/ee476/FinalProjects/s2009/bhp7_teg25/bhp7_teg25/
#http://everything2.com/index.pl?node_id=925418
