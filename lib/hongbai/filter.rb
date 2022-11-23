module Hongbai
  class Filter
    def initialize
      @a0 = 0
      @a1 = 0
      @a2 = 0
      @a3 = 0
      @a4 = 0
      @a5 = 0
      @a6 = 0
      @a7 = 0
    end

    def apply(input)
      ret = (@a7 + input) / 20
      @a7 = @a6 + input * 2
      @a6 = @a5 + input * 3
      @a5 = @a4 + input * 4
      @a4 = @a3 + input * 4
      @a3 = @a2 + input * 3
      @a2 = @a1 + input * 2
      @a1 = @a0 + input
      @a0 = input
      ret
    end

    def steps; 8 end
  end
end
