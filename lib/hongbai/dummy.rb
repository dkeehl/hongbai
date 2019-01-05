module Hongbai
  module Dummy
    class Window; end

    class Video
      def initialize(_win); end

      def display(_colors); end
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

      def reset
        @cycle = 0
      end

      def []=(n, x); @array[n] = x end

      def [](n); @array[n] end

      alias_method :fetch, :read
      alias_method :dummy_read, :read
      attr_reader :cycle
    end

    class Input
      def poll; end
      
      def read_4016(_addr); 0x40 end

      def read_4017(_addr); 0x40 end

      def write_4016(_addr, _val); end
    end
  end
end
