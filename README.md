# Envelopes

Envelopes and partition tables for Toit.

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

See the [variants/README.md](variants/README.md) for a list of the
most commonly used variants. You can also browse the `variants`
directory for more variants.

See the [partitions/esp32/README.md](partitions/esp32/README.md) for
a list of the most commonly used partition tables. You can also browse
the `partitions/esp32` directory for more partition tables.

Since SDK v2.0.0-alpha.195 the flash size is derived from the partition
table during flashing, so any envelope can be combined with any partition
table. There is no longer a need for envelopes built for a specific flash
size, such as the dedicated 16MB envelopes.

## EC618

To build an EC618 (Air780E) envelope, check out a Toit revision with EC618
support and install CMake, Ninja, curl, sha256sum (or shasum), and GNU Arm
10.3-2021.10. Then run:

```sh
make build-ec618 EC618_GCC_PATH=/path/to/gcc-arm-none-eabi-10.3-2021.10
```

This reads `toit/toolchains/ec618/base-version` and downloads the matching
`ec618-base-vN` release from `toitlang/toit`. The released base artifacts are
cached under `build/ec618-bases/` and their SHA-256 checksums are verified
before every build. A missing release or checksum failure stops the build;
the base is never rebuilt locally.

The command builds the host tools, then builds and validates the VM slots
against the published base. The envelope, including that base, is written
to `build/ec618/firmware.envelope`.
EC618 uses the Toit SDK's build directly; it does not use ESP-IDF variants or
the `synthesize` command. See the checked-out SDK's `README.ec618.md` for
base compatibility and flashing instructions.

The Build workflow's `build-ec618` input enables EC618 builds and produces
`firmware-ec618.envelope.gz` alongside the other release envelopes.
The chosen SDK revision must reference a published base release; a newer base
cannot replace the required version. To test a newer SDK before its next release,
set the workflow's branch override to `main` and disable release uploads.
