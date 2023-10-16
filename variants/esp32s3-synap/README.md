# ESP32-SYNAP

A variant of the ESP32 envelope that changes the default UART RX pin to
pin 7. This frees up the default RX pin (44) for use as a GPIO.

Also sets the size of the OTA partitions to 0x1C0000 (1835008) bytes.

As a consequence the size of the programs partition is set to
0x60000 (393216) bytes.
