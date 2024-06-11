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

## Variants

### esp32

A generic ESP32 variant. This is the default variant when using Toit.
It is built for maximum compatibility.

This variant supports Ethernet, but without the clock output.

### esp32-spiram

An ESP32 variant for boards with SPIRAM. Otherwise the same as the ESP32 variant.

### esp32-eth-clk-out0 and esp32-eth-clk-out17

A variant for ESP32 boards with Ethernet and a clock output on pin 0/17.

Olimex boards with Ethernet should use this variant. The WROOM versions need
`esp32-eth-clk-out17` and the WROVER versions need `esp32-eth-clk-out0`.

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

### esp32-no-ble

A [variant](variants/esp32-no-ble/) for ESP32 boards.  This variant
saves some RAM and flash space by removing the Bluetooth stack.
The saved IRAM enables us to make the Toit interpreter a little faster
and add support for external RAM (PSRAM, aka SPIRAM).

## Contributing

Feel free to open issues and pull requests with new variants. Make sure
they have a description (README.md) with the purpose and the changes.
We will automatically build them whenever a new Toit version is released.

Note that some variants are featured here. Consult the
Toit team before adding new variants to this README.

### Creating a variant

Variants are created by copying an existing variant and making the
necessary changes. These consists of either overwriting existing files
or by applying patches.

#### Partition changes

For partition changes, simply copy the new `partitions.csv` into the
variant directory. The `esp32-ota-1c0000` is an example of this where
the OTA partition size has been increased.

#### sdkconfig changes

For `sdkconfig` changes, a patch to the original `sdkconfig.defaults`
file is typically preferred.

For example, to create a variant `esp32s3-foo`.
* Check out Toit (or use an existing checkout).
* Copy the existing `toolchains/esp32s3` directory to `toolchains/esp32s3-foo`:
  `cp -r toolchains/esp32s3 toolchains/esp32s3-foo`.
* Run `make IDF_TARGET=esp32s3 ESP32_CHIP=esp32s3-foo menuconfig` and make the changes you want.
  This automatically updates the `sdkconfig.defaults` as well.
* Create patch by running:
  ```
  diff -aur \
    --label toit/toolchains/esp32s3/sdkconfig.defaults \
    --label synthesized/esp32s3-foo/sdkconfig.defaults \
    toolchains/esp32s3/sdkconfig.defaults \
    toolchains/esp32s3-foo/sdkconfig.defaults \
    > toolchains/esp32s3-foo/sdkconfig.defaults.patch
  ```
  The labels are not crucial, but make it easier for us to update the
  patch at a later time.
* Create a new variant in this (`envelopes`) repository and copy the patch file into it.

#### Main changes

For changes to the `main` directory (be it the `toit.c` or the `CMakelists.txt` in it),
use a recursive diff to create a patch on the original `main` directory.

The synthetization tool will use the flag `-p1` when applying the patch.
