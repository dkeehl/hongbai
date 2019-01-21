module Hongbai
  module Mapper
    # Setup
    def mapper_init(_prg_rom, _chr_rom); end

    # Returns a pattern table
    # A pattern table is an object which has a method #[] : Interger -> Array
    # the integer is in range (0..0x1000), the array is of size 8.
    def pattern_table; end

    def prg_read_method(_addr); end

    def prg_write_method(_addr); end

    def chr_read_method(_addr); end

    def chr_write_method(_addr); end
  end
end
