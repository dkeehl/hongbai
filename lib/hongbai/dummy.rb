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
      end

      def fetch(n); @arrsy[n] end

      def read(n); @array[n] end

      def load(n, x); @array[n] = x end
    end

    class Input
      def poll; end
      
      def read_4016; 0 end

      def read_4017; 0 end

      def store(_); end
    end
  end
end
