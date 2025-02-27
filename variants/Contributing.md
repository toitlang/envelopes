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
* Create the following environment variables: `BASE=esp32s3` and
  `VARIANT=esp32s3-foo`. (Adjust for your base and variant).
* Create the new variant directory: `mkdir -p variants/$VARIANT`.
* Check out Toit (or use an existing checkout) as `toit` in the root of
  this repository. Symbolic links are fine.
* Move into the `toit` directory: `cd toit`.
* Copy the existing `toolchains/$BASE` directory to `toolchains/$VARIANT`:
  `cp -r toolchains/$BASE toolchains/$VARIANT`.
* Run `make IDF_TARGET=$BASE ESP32_CHIP=$VARIANT menuconfig` and make the changes you want.
  This automatically updates the `sdkconfig.defaults` as well.
* Move back to the root of the repository: `cd ..`.
* Create patch by running:
  ```
  diff -aur \
    --label toit/toolchains/$BASE/sdkconfig.defaults \
    --label synthesized/$VARIANT/sdkconfig.defaults \
    toolchains/$BASE/sdkconfig.defaults \
    toolchains/$VARIANT/sdkconfig.defaults \
    > variant/$VARIANT/sdkconfig.defaults.patch
  ```
  The labels are not crucial, but make it easier for us to update the
  patch at a later time.

### Main changes

For changes to the `main` directory (be it the `toit.c` or the `CMakelists.txt` in it),
use a recursive diff to create a patch on the original `main` directory.

The synthetization tool will use the flag `-p1` when applying the patch.
