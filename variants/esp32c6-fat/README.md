# ESP32C6-FAT

A variant of the ESP32C6 envelope that includes support for the FAT
filesystem (SD cards and FAT partitions on flash).

The default ESP32C6 envelope does not include the FAT filesystem
primitives. Use this variant if you need to mount a FAT filesystem,
for example to access an SD card.
