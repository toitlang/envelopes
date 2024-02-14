# ESP32-SEDISTO

A variant of the ESP32 envelope that supports ethernet. The ESP32
outputs the PHY's clock on pin 0. This variant furthermore enables
SPIRAM.

Since Bluetooth and SPIRAM support use some memory, the Toit interpreter
doesn't fit into the SPIRAM anymore. As such, Toit programs may run
slower on this variant.

This firmware also increases the partition sizes to 0x1c0000 bytes.

Support for displays (fonts, drawing primitives) is not included.

Support for FATFS (SD card) is not included.
