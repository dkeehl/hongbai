module Hongbai
  module Dummy
    class Video
      def display(_colors); end
    end

    class Audio
      def process(_); end
    end

    class Input
      def poll; end
      
      def read_4016(_addr); 0x40 end

      def read_4017(_addr); 0x40 end

      def write_4016(_addr, _val); end
    end
  end
end
