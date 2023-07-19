# Envelopes

Envelopes for Toit.

This repository contains a tool to generate envelopes for Toit. It
also automatically builds envelopes for the variants that are stored in
this repository.

For the tool see [the Envelope Tool README](tools/README.md).

We call "variant" configurations (mostly `sdkconfig`) that produce
different builds of firmwares. For example, the `esp32-eth-clk-out17`
variant is for a firmware that uses Ethernet and has the clock output
on pin 17 (like the Olimex Ethernet boards).

Compiled envelopes for specific SDK versions are found in the
release page of this repository. For example, envelopes that are
compiled with and for SDK v2.0.0-alpha.90 are found on the
[v2.0.0-alpha.90 release](https://github.com/toitlang/envelopes/releases/tag/v2.0.0-alpha.90)
page.

## Contributing

Feel free to open issues and pull requests with new variants. Make sure
they have a description (README.md) with the purpose and the changes.
We will automatically build them whenever a new Toit version is released.

Note that some variants are featured here. Consult the
Toit team before adding new variants to this README.

## Variants

### esp32

A generic ESP32 variant. This is the default variant when using Toit.
It is built for maximum compatibility.

This variant supports Ethernet, but without the clock output.

### esp32-eth-clk-out17

A variant for ESP32 boards with Ethernet and a clock output on pin 17.

Olimex boards with Ethernet should use this variant.

### esp32c3

A generic [ESP32-C3 variant](variants/esp32c). This is the default variant
when using Toit on ESP32-C3 boards.

### esp32s2

A generic [ESP32-S2 variant](variants/esp32s2). This is the default variant
when using Toit on ESP32-S2 boards.

### esp32s3

A generic [ESP32-S3 variant](variants/esp32s3). This is the default variant
when using Toit on ESP32-S3 boards.

This variant is configured for external Quad PSRAM.

### esp32s3-spiram-octo

A [variant](variants/esp32s3-spiram-octo/) for ESP32-S3 boards with external
octal PSRAM.

These boards are faster, but often more expensive.
