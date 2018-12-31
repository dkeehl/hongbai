module Hongbai
  # This algorithm is copied from the Pinky project
  # (https://github.com/koute/pinky)
  class Filter
    def initialize
      @delay_00 = 0.0
      @delay_01 = 0.0
      @delay_02 = 0.0
      @delay_03 = 0.0
      @delay_04 = 0.0
      @delay_05 = 0.0
    end

    def apply(input)
      v17 = 0.88915976376199868 * @delay_05
      v14 = -1.8046931203033707 * @delay_02
      v22 = 1.0862126905669063 * @delay_04
      v21 = -2.0 * @delay_01
      v16 = 0.97475300535003617 * @delay_04
      v15 = 0.80752903209625071 * @delay_03
      v23 = 0.022615049608677419 * input
      v12 = -1.7848029270188865 * @delay_00
      v04 = -v12 + v23
      v07 = v04 - v15
      v18 = 0.04410421960695305 * v07
      v13 = -1.8500161310426058 * @delay_01
      v05 = -v13 + v18
      v08 = v05 - v16
      v19 = 1.0876279697671658 * v08
      v10 = v19 + v21
      v11 = v10 + v22
      v06 = v11 - v14
      v09 = v06 - v17
      v20 = 1.3176796030365203 * v09
      output = v20
      @delay_05 = @delay_02
      @delay_04 = @delay_01
      @delay_03 = @delay_00
      @delay_02 = v09
      @delay_01 = v08
      @delay_00 = v07

      output
    end
  end
end
