# Contributing

Feel free to open issues and pull requests with new variants. Make sure
they have a description (README.md) with the purpose and the changes. If
they are generally useful, we will add them to the repository.

Variants in this repository are automatically built whenever a new Toit
version is released.

## Creating a variant

Variants are created by copying an existing variant and making the
necessary changes. These consists of either overwriting existing files
or by applying patches.

### Partition changes

For partition changes, simply copy the new `partitions.csv` into the
variant directory. The `esp32-ota-1c0000` is an example of this where
the OTA partition size has been increased.

### sdkconfig changes

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

### Main changes

For changes to the `main` directory (be it the `toit.c` or the `CMakelists.txt` in it),
use a recursive diff to create a patch on the original `main` directory.

The synthetization tool will use the flag `-p1` when applying the patch.
