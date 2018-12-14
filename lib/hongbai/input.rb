module Hongbai
  class Controller
    BUTTON_A = 0
    BUTTON_B = 1
    BUTTON_SELECT = 2
    BUTTON_START = 3
    BUTTON_UP = 4
    BUTTON_DOWN = 5
    BUTTON_LEFT = 6
    BUTTON_RIGHT = 7

    def initialize(key_map)
      @key_map = key_map
      @buttons = Array.new(8, false)
      @current = BUTTON_A
      @strobe = false
    end

    def handle_key(key_ev, value)
      case key_ev.sym
      when @key_map.a then @buttons[BUTTON_A] = value
      when @key_map.b then @buttons[BUTTON_B] = value
      when @key_map.select then @buttons[BUTTON_SELECT] = value
      when @key_map.start then @buttons[BUTTON_START] = value
      when @key_map.up then @buttons[BUTTON_UP] = value
      when @key_map.down then @buttons[BUTTON_DOWN] = value
      when @key_map.left then @buttons[BUTTON_LEFT] = value
      when @key_map.right then @buttons[BUTTON_RIGHT] = value
      end
    end

    def read
      if @current < 8
        ret = @buttons[@current] ? 1 : 0
        @current += 1 unless @strobe
        ret
      else
        1
      end
    end

    def reset_state
      @current = BUTTON_A
    end

    def write(byte)
      @strobe = (byte & 1) == 1
      reset_state if @strobe
    end
  end

  class KeyMap < Struct.new(:a, :b, :select, :start, :up, :down, :left, :right)
    def self.default_1p
      new(SDL2::Key::K,
          SDL2::Key::J,
          SDL2::Key::SPACE,
          SDL2::Key::RETURN,
          SDL2::Key::W,
          SDL2::Key::S,
          SDL2::Key::A,
          SDL2::Key::D)
    end
  end

  class Input
    def initialize(device)
      @device = device

      # Ouput port. 3 bits
      @out = 0
    end

    def poll
      while ev = SDL2::Event.poll
        case ev
        when SDL2::Event::Quit
          exit
        when SDL2::Event::KeyDown
          @device.handle_key(ev, true)
        when SDL2::Event::KeyUp
          @device.handle_key(ev, false)
        end
      end
    end

    # Read from $4016
    def read_4016
      @device.read
    end

    # Read from $4017
    def read_4017
      0
    end

    # Only accepts writing to $4016
    def store(val)
      @out = val & 7
      @device.write(@out)
    end
  end
end
