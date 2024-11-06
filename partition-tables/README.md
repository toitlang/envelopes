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
