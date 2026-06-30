# Partition tables

This directory contains partition tables for ESP32 devices and their variants.

During flashing, users can override the default partition table that comes
with the envelope that they are flashing.

Here is a list of the most commonly used partition tables:

## OTA-1C0000

A partition table that sets the size of the OTA partitions
to 0x1C0000 (1835008) bytes. This table is typically used for
use-cases where programs are bundled with the firmware (like with
[Artemis](https://github.com/toitware/artemis)).

## OTA-1D0000

A partition table that sets the size of the OTA partitions
to 0x1D0000 (1900544) bytes. This table reserves even more space for
the OTA partitions.

## OTA-200000, OTA-300000, OTA-400000

Partition tables with larger OTA partitions, for firmware images that bundle
large assets (assets are stored inside the OTA partition together with the
firmware). They set the OTA partitions to 0x200000 (2MB), 0x300000 (3MB) and
0x400000 (4MB) respectively.

Because there are two OTA partitions, these already occupy 4MB, 6MB and 8MB
respectively, so they are only provided for 16MB (and larger) flash sizes.

## -8MB, -16MB, -32MB

The 8MB, 16MB, and 32MB variants are for devices with flash sizes of
8MB, 16MB, and 32MB respectively. For each of them the additional space
is allocated as a data partition.
