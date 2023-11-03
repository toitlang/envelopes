# ESP32-QEMU

A variant of the ESP32 envelope that has network connectivity
when running on QEMU.

It also sets the size of the OTA partitions to 0x1C0000 (1835008) bytes.

As a consequence the size of the programs partition is set to
0x60000 (393216) bytes.

## Running on QEMU

Use Toit's `firmware` tool:

```bash
firmware extract -e some.envelope --format qemu -o image.bin
```

Then run the image with QEMU:

``` bash
qemu-system-xtensa \
    -M esp32 \
    -nographic \
    -drive file=image.bin,format=raw,if=mtd \
    -nic user,model=open_eth \
    -s
```
You might need to add `-L` with the path to the folder containing the
`esp32-v3-rom.bin` file.
