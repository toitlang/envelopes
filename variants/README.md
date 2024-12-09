# Variants

Some commonly used variants are featured here. You can also browse this
directory for more variants.

See the [Contributing](Contributing.md) guide for how to create a new variant.


## esp32

A generic ESP32 variant. This is the default variant when using Toit.
It is built for maximum compatibility.

This variant supports Ethernet, but without the clock output.

## esp32-spiram

An ESP32 variant for boards with SPIRAM. Otherwise the same as the ESP32 variant.

## esp32-no-ble

A [variant](esp32-no-ble/) for ESP32 boards.  This variant
saves some RAM and flash space by removing the Bluetooth stack.
The saved IRAM enables us to make the Toit interpreter a little faster
and add support for external RAM (PSRAM, aka SPIRAM).

## esp32-eth-clk-out0 and esp32-eth-clk-out17

A variant for ESP32 boards with Ethernet and a clock output on pin 0/17.

Olimex boards with Ethernet should use this variant. The WROOM versions need
`esp32-eth-clk-out17` and the WROVER versions need `esp32-eth-clk-out0`.

## esp32c3

A generic [ESP32-C3 variant](esp32c3). This is the default variant
when using Toit on ESP32-C3 boards.

## esp32c6

A generic [ESP32-C6 variant](esp32c6). This is the default variant
when using Toit on ESP32-C6 boards.

## esp32s2

A generic [ESP32-S2 variant](esp32s2). This is the default variant
when using Toit on ESP32-S2 boards.

## esp32s3

A generic [ESP32-S3 variant](esp32s3). This is the default variant
when using Toit on ESP32-S3 boards.

This variant is configured for external Quad PSRAM.

## esp32s3-spiram-octo

A [variant](esp32s3-spiram-octo/) for ESP32-S3 boards with external
octal PSRAM.

These boards are faster, but often more expensive.
