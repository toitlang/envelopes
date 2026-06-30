# ESP32-SPIRAM-REV3

A variant of the [ESP32-SPIRAM](../esp32-spiram/) envelope for boards
with SPIRAM (external memory) that are built around an **ESP32 chip of
revision v3.0 (ECO3) or newer**.

Like `esp32-spiram` it keeps Bluetooth/BLE enabled, but unlike
`esp32-spiram` it also keeps the Toit interpreter in IRAM, which makes
the interpreter run faster.

## Why a separate variant?

On the original ESP32 silicon (revisions v1.x) there is a hardware bug
in the SPI RAM cache. When SPIRAM is enabled, ESP-IDF compiles in a
workaround that moves a substantial amount of code into IRAM. Together
with BLE there is then not enough IRAM left to also keep the Toit
interpreter in IRAM, so the regular `esp32-spiram` variant moves the
interpreter to flash (`CONFIG_TOIT_INTERPRETER_IN_IRAM=n`).

The cache bug was fixed in chip revision v3.0, so on those chips the
workaround is not needed. This variant requires revision v3.0+
(`CONFIG_ESP32_REV_MIN_3=y`), which disables the workaround and frees
enough IRAM to keep the interpreter in IRAM.

## Can I use this variant?

You can use it only if your board's ESP32 chip is **revision v3.0 or
newer**. Most ESP32 chips manufactured since around 2020 are v3.0 or
later, but older modules (including many early WROVER boards) are not.

To check the revision of a connected board, run esptool and look at the
chip description it prints, for example:

```
esptool.py --chip esp32 chip_id
```

It prints a line such as `Chip is ESP32-D0WD-V3 (revision v3.0)`. The
`-V3` / `revision v3.0` (or higher) means the chip is supported; a
`revision v1.x` chip is not.

You do not have to get this right by hand: the firmware checks the chip
revision itself at boot. If you flash this envelope onto a chip that is
too old, the second-stage bootloader refuses to start the application
and prints an error like:

```
E (...) boot: Image requires chip rev >= v3.0, but chip is v1.0
```

It never runs the broken firmware, so installing this envelope on an
unsupported chip is safe: when it arrives as an OTA update, the bootloader
rolls back to the previously installed firmware. If you see that message,
use the regular [`esp32-spiram`](../esp32-spiram/) variant instead, which
runs on every ESP32 revision.
