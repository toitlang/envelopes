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
