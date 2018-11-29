require 'tk'
require 'tkextlib/tile'
require 'bindata'
require_relative 'cpu'
require_relative 'assembler'

class TestCpu < Cpu
  def initialize
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
    @pc.load 0
  end

  def reset
    @counter = 0
    @a.load 0
    @x.load 0
    @y.load 0
    @p.load 0x20
    @pc.load 0
    @sp.load 0xff
    @m.map! { 0 }
  end

  def load_data(array, pc)
    reset
    array.each_with_index { |n, i| @m[i] = n }
    @pc.load pc
  end

  def accumulator16
    '%02x' % @a.value
  end

  def x_register16
    '%02x' % @x.value
  end

  def y_register16
    '%02x' % @y.value
  end

  def pc16
    '%04x' % @pc.value
  end

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
    '%02x' % @sp.value
  end

  def opcode_text
    opcode = @m.fetch(@pc.value)
    c = decode(opcode)
    "#{c[0].to_s.upcase}_#{@short_addr_mode[c[1]]}"
  end

  def interrupt?
    @p.interrupt_disabled?
  end
end


class Memviewer
  @cpu = TestCpu.new
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
  #register status
  @status = {'cycle' => @cycle,
            'a' => @a,
            'x' => @x,
            'y' => @y,
            'p' => @p,
            'pc' => @pc,
            'sp' => @sp,
            'instruction' => @instruction,
          }

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
    if i.odd?
      l.background = 'white'
    else
      l.background = '#e3e9ff'
    end
  end

  ##buttons
  @bottons = [
    Tk::Tile::Button.new(@root) {text 'Assemble'; command {Memviewer.assemble} }.grid(:sticky => 'w'),
    Tk::Tile::Button.new(@root) {text 'Run by step'; command {Memviewer.run_by_step} }.grid(:sticky => 'w'),
    Tk::Tile::Button.new(@root) {text 'Run'; command {Memviewer.run} }.grid(:sticky => 'w')
  ]

  #input area
  @text = Tk::Text.new(@root) {width 20; height 10}.grid(:sticky => 'w')


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
      35.times do
        @cpu.excute_cycle
        # puts  "#{@cpu.pc16} #{@cpu.opcode_text} "\
        #       "x:#{@cpu.x_register} "\
        #       "59:#{@cpu.mem[0x59]}"
      end
    end


    def run_by_step
      clear_pc_tag
      @cpu.excute_cycle
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
      @cycle.value = @cpu.cycle
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
      @m.each_with_index { |v, i| v.value = '%02x' % @cpu.mem[@page * 256 + i] }
    end

    def change_first_column
      @c1.each do |l|
        l.text = "#{@page_text}#{l.text[-2..-1]}"    
      end
    end
  end


  f = File.binread('6502_functional_test.bin').unpack('C*')
  #program = TestingProgram.read(f).data
  pading = Array.new(10, 0xff)
  f = pading + f
  @cpu.load_data(f, 0x2b48)

  #run
  refresh_data
  tag_pc
  Tk.mainloop
end
