module Hongbai
  module Dummy
    class Window
      def create_renderer(_, _)
        Renderer.new
      end
    end

    class Renderer
      def present; end

      def draw_color=(_); end

      def draw_point(_, _); end
    end

    class Mem
      def initialize
        @array = Array.new(0x10000, 0)
        @cycle = 0
      end

      def read(n)
        @cycle += 1
        @array[n]
      end

      def load(n, x)
        @cycle += 1
        @array[n] = x
      end

      def []=(n, x); @array[n] = x end

      alias_method :fetch, :read
      alias_method :dummy_read, :read
      attr_reader :cycle
    end

    class Input
      def poll; end
      
      def read_4016; 0 end

      def read_4017; 0 end

      def store(_); end
    end
  end
end
