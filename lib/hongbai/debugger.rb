require 'tk'
require 'tkextlib/tile'
require_relative 'cpu'
require_relative 'assembler'
require_relative 'dummy'

class Buffer
  def initialize(size)
    @arr = Array.new(size)
    @pos = 0
    @size = size
  end

  def <<(x)
    @arr[@pos] = x
    @pos = (@pos + 1) % @size
  end

  def to_s
    count = 0
    i = @pos - 1
    str = ""
    while count < @size
      str += "step #{@size - count}: #{@arr[i].to_s}\n"
      i -= 1
      count += 1
    end
    str
  end

  def reset
    @pos = 0
    @arr.map! {nil}
  end
end

module Hongbai
  class TestCpu < Cpu
    def initialize(mem)
      super
      @short_addr_mode = {
        :immediate => 'IMM',
        :zero_page => 'ZP',
        :zero_page_x => 'ZPX',
        :zero_page_y => 'ZPY',
        :absolute => 'AB',
        :absolute_x => 'ABX',
        :absolute_y => 'ABY',
        :indirect => 'IN',
        :indirect_x => 'INX',
        :indirect_y => 'INY',
        :accumulator => 'AC',
        :implied => 'IMP',
        :relative => 'REL',
      }
      @log = Buffer.new(20)
      @pre_start = nil
      @this_start = @pc.value
      @this_end = nil
    end

    attr_reader :log

    def reset
      @a = 0
      @x = 0
      @y = 0
      @p.load 0x20
      @pc.load 0
      @sp = 0xff
      @m.send(:initialize)
      @log.reset
      @pre_start = nil
      @this_start = @pc.value
      @this_end = nil
    end

    def step
      @pre_start = @this_start
      @this_start = @pc.value
      @log << OP_TABLE[@m[@pc.value]]
      super
      @this_end = @pc.value
    end

    def looping?
      @this_end == @pre_start
    end

    def load_data(array, pc)
      reset
      array.each_with_index {|n, i| @m[i] = n }
      @pc.load pc
      @this_start = pc
    end

    def accumulator16
      '%02x' % @a
    end

    def x_register16
      '%02x' % @x
    end

    def y_register16
      '%02x' % @y
    end

    def pc16
      '%04x' % @pc.value
    end

    def pc; @pc.value end

    def p_register_text
      flags = ['c', 'z', 'i', 'd', 'b', '-', 'v', 'n']
      p_text = Array.new(8)
      flags.each_with_index do |f, i|
        if @p.value >> i & 1 == 1
          p_text[7 - i] = f.upcase
        else
          p_text[7 - i] = f.downcase
        end
      end
      p_text.join
    end

    def stack_pointer16
      '%02x' % @sp
    end

    def opcode_text
      opcode = @m.fetch(@pc.value)
      c = Hongbai::Cpu::OP_TABLE[opcode]
      "#{c[0].to_s.upcase}_#{@short_addr_mode[c[1]]}"
    end

    def interrupt?
      @p.interrupt_disabled?
    end
  end
end

module Memviewer
  @mem = Hongbai::Dummy::Mem.new
  @cpu = Hongbai::TestCpu.new(@mem)
  @asm = Assembler.new

  @root = TkRoot.new {title '6502 CPU DEBUGGER'}
  status_area = Tk::Tile::Frame.new(@root).grid(:sticky => 'sew')

  @cycle = TkVariable.new
  @a = TkVariable.new
  @x = TkVariable.new
  @y = TkVariable.new
  @p = TkVariable.new
  @pc = TkVariable.new
  @sp = TkVariable.new
  @m = Array.new(16 * 16) { TkVariable.new }
  @page = 0
  @page_text = TkVariable.new('00')
  @pc_tag = nil
  @instruction = TkVariable.new

  class << self
    attr_reader :cycle, :a, :x, :y, :p, :pc, :sp, :instruction
  end

  statu_names = [
    Tk::Tile::Label.new(status_area) {text 'cycle'; width 8},
    Tk::Tile::Label.new(status_area) {text 'a'; width 8},
    Tk::Tile::Label.new(status_area) {text 'x'; width 8},
    Tk::Tile::Label.new(status_area) {text 'y'; width 8},
    Tk::Tile::Label.new(status_area) {text 'p'; width 10},
    Tk::Tile::Label.new(status_area) {text 'pc'; width 8},
    Tk::Tile::Label.new(status_area) {text 'sp'; width 8},
    Tk::Tile::Label.new(status_area) {text 'instruction'; width 10},
  ]

  statu_names.each_with_index do |l, i|
    l.background = '#bbccff'
    l.anchor = 'center'
    l.grid(:row => 1, :column => i + 1)
  end

  statu_values = [
    Tk::Tile::Label.new(status_area) {textvariable Memviewer.cycle; width 8},
    Tk::Tile::Label.new(status_area) {textvariable Memviewer.a; width 8},
    Tk::Tile::Label.new(status_area) {textvariable Memviewer.x; width 8},
    Tk::Tile::Label.new(status_area) {textvariable Memviewer.y; width 8},
    Tk::Tile::Label.new(status_area) {textvariable Memviewer.p; width 10},
    Tk::Tile::Label.new(status_area) {textvariable Memviewer.pc; width 8},
    Tk::Tile::Label.new(status_area) {textvariable Memviewer.sp; width 8},
    Tk::Tile::Label.new(status_area) {textvariable Memviewer.instruction; width 10},
  ]

  statu_values.each_with_index do |l, i|
    l.anchor = 'center'
    l.grid(:row => 2, :column => i + 1)
    l.background = i.odd? ? 'white' : '#e3e9ff'
  end

  ##buttons
  _buttons = [
    Tk::Tile::Button.new(@root) {text 'Assemble'; command {Memviewer.assemble} }.grid(:sticky => 'w'),
    Tk::Tile::Button.new(@root) {text 'Run by step'; command {Memviewer.run_by_step} }.grid(:sticky => 'w'),
    Tk::Tile::Button.new(@root) {text 'Run'; command {Memviewer.run} }.grid(:sticky => 'w')
  ]

  #input area
  _text = Tk::Text.new(@root) {width 20; height 10}.grid(:sticky => 'w')

  #create the memory map
  memory_map = Tk::Tile::Frame.new(@root).grid(:sticky => 'w')
  first_row = Tk::Tile::Frame.new(memory_map).grid(:sticky => 'se', :row => 1, :column => 2)
  first_column = Tk::Tile::Frame.new(memory_map).grid(:sticky => 'w', :row => 2, :column => 1)
  data_map = Tk::Tile::Frame.new(memory_map).grid(:sticky => 'w', :row => 2, :column => 2)
  hexs = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']

  r1 = Array.new(16) { Tk::Tile::Label.new(first_row) {width 4; anchor 'center'}.grid(:sticky => 'w') }
  @c1 = Array.new(16) { Tk::Tile::Label.new(first_column) {width 7; anchor 'center'}.grid(:sticky => 's') }

  hexs.each_with_index do |n, i|
    r1[i].text = n
    r1[i].grid(:row => 1, :column => i)
    @c1[i].text = "#{@page_text}#{n}:"
  end

  @mem_data = Array.new(16 * 16) { Tk::Tile::Label.new(data_map) {width 4; anchor 'center'; background 'white'} }
  @mem_data.each_with_index do |l, i|
    #addr = @page << 8 | i
    l.textvariable = @m[i]
    l.grid(:row => i / 16 + 1, :column => i % 16 + 1)
  end

  #select page
  page_selector = Tk::Tile::Combobox.new(memory_map)
  page_selector.values = (0..255).to_a.map { |i| '%02x' % i }
  page_selector.width = 4
  page_selector.justify = 'right'
  page_selector.textvariable = @page_text
  page_selector.bind('<ComboboxSelected>') { Memviewer.change_page }
  page_selector.grid(:row => 1, :column => 1)

  #commands
  class << self
    def run
      loop do
        @cpu.step
        break if @cpu.looping?
      end
      STDERR.puts "looping at cycle #{@mem.cycle}"
      STDERR.puts @cpu.log.to_s
    end

    def run_by_step
      clear_pc_tag
      @cpu.step
      refresh_data
      tag_pc
    end

    def assemble
      source = @text.get(1.0, 'end')
      code = @asm.eval source
      clear_pc_tag
      @cpu.load_data(code, 0)
      refresh_data
      tag_pc
      #@text.delete(1.0, 'end')
    end

    def refresh_data
      @cycle.value = @mem.cycle
      @a.value = @cpu.accumulator16
      @x.value = @cpu.x_register16
      @y.value = @cpu.y_register16
      @p.value = @cpu.p_register_text
      @pc.value = @cpu.pc16
      @sp.value = @cpu.stack_pointer16
      @instruction.value = @cpu.opcode_text
      refresh_m
    end

    def tag_pc
      if @cpu.pc >> 8 == @page
        @pc_tag = @cpu.pc & 0xff
        @mem_data[@pc_tag].background = 'yellow'
      end
    end

    def clear_pc_tag
      if @pc_tag
        @mem_data[@pc_tag].background = 'white'
      end
    end

    def change_page
      if @page_text.value.to_i(16) != @page
        @page = @page_text.value.to_i(16)
        clear_pc_tag
        refresh_m
        change_first_column
        tag_pc
      end
    end

    def refresh_m
      @m.each_with_index { |v, i| v.value = '%02x' % @mem[@page * 256 + i] }
    end

    def change_first_column
      @c1.each do |l|
        l.text = "#{@page_text}#{l.text[-2..-1]}"    
      end
    end
  end

  path = File.expand_path("../../../nes/6502_functional_test.bin", __FILE__)
  f = File.binread(path).unpack('C*')
  pading = Array.new(10, 0xff)
  f = pading + f
  @cpu.load_data(f, 0x2b48)

  run
  refresh_data
  tag_pc
  Tk.mainloop
end
