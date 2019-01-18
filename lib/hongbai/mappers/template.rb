module Hongbai
  module Mapper
    # Setup
    def mapper_init; end

    # Returns a pattern table
    # A pattern table is an object which has a method #[] : Interger -> Array
    # the integer is in range (0..(511 * 8)), the array is of size 8.
    def pattern_table; end

    def prg_read_method; end

    def prg_write_method; end

    def chr_read_method; end

    def chr_write_method; end
  end
end
