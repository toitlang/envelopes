# OTA-400000-16MB

A partition table for 16MB flash that sets the size of the OTA partitions
to 0x400000 (4194304) bytes.

This is useful for firmware images that bundle large assets, which are stored
inside the OTA partition together with the firmware. The smaller OTA tables
(like OTA-1D0000 at 0x1D0000) are not large enough to hold such images.

The programs partition is set to 0x100000 (1048576) bytes, and the remaining
0x6E0000 (7208960, ~6.9MB) of the flash is allocated as a data partition.

Note that two OTA partitions of this size already occupy 8MB on their own, so
this table is only provided for 16MB (and larger) flash sizes.
