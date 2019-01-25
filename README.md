## Hongbai: A NES emulator

This project is aimed mainly for learning.

### Usage
SDL 2.0.4 or later is required.

    $ gem install ffi
    $ git clone http://github.com/dkeehl/hongbai.git
    $ cd hongbai
    $ ./bin/hongbai path/to/rom.nes

|key   |button |
|------|-------|
|`W`   |Up     |
|`S`   |Down   |
|`A`   |Left   |
|`D`   |Right  |
|`K`   |A      |
|`J`   |B      |
|return|Start  |
|space |Select |

### Supported mappers

* NROM  (0)
* MMC1  (1)
* UxROM (2)
* CNROM (3)
* MMC3  (4)

### Acknowledgement

Thanks to [NESdev](nesdev.com) for the great documents and testing roms.

Thanks to [sprocketnes](https://github.com/pcwalton/sprocketnes)
and [pinky](https://github.com/koute/pinky) which helped me understanding the PPU and APU.
