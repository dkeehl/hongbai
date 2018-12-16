require_relative './sdl2'

module Hongbai
  module SDL2
    module Key
      alpha = ('a'..'z')
      blank = {
        SPACE: ' ',
        TAB: "\t",
      }
      control = {
        RETURN: "\r",
      }
      alpha.each {|c| const_set(c.upcase, c.unpack('C')[0]) }
      control.merge(blank).each do |name, char|
        const_set(name, char.unpack('C')[0])
      end
    end

    module Event 
      class KeyboardEvent < FFI::Struct
        layout(
          :type,      :uint32,
          :timestamp, :uint32,
          :windowID,  :uint32,
          :state,     :uint8,
          :repeat,    :uint8,
          :padding2,  :uint8,
          :padding3,  :uint8,
          :scancode,  :int,
          :sym,       :int,
        )
      end

      KEY_DOWN = 0x300
      KEY_UP   = 0x301
      QUIT     = 0x100

      @event = FFI::MemoryPointer.new(:uint32, 16)
      @keyboard_repeat_offset = KeyboardEvent.offset_of(:repeat)
      @keyboard_sym_offset = KeyboardEvent.offset_of(:sym)

      def self.poll(handler)
        while SDL2.PollEvent(@event) != 0
          case ev = @event.read_int
          when KEY_DOWN, KEY_UP
            next if @event.get_uint8(@keyboard_repeat_offset) != 0
            key_code = @event.get_int(@keyboard_sym_offset)
            handler.handle_key(key_code, ev == KEY_DOWN)
          when QUIT
            exit
          end
        end
      end
    end
  end
end
