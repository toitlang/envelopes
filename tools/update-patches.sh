#!/bin/bash

# First argument is the before hash/tag; second the after.
BEFORE=$1
AFTER=$2

# Save the current directory.
CURRENT_DIR=$(pwd)

cd toit
git checkout $BEFORE
git submodule update --init --recursive

cd $CURRENT_DIR

make synthesize-all

cd toit
git checkout $AFTER
git submodule update --init --recursive
source third_party/esp-idf/export.sh

cd $CURRENT_DIR
cd synthesized
VARIANTS=$(ls -d esp32*)
cd $CURRENT_DIR

for d in $VARIANTS; do
  if [[ -e variants/$d/sdkconfig.defaults.patch ]]; then
    export IDF_TARGET=$(echo $d | cut -d'-' -f1)
    idf.py -C synthesized/$d -B synthesized/$d/build save-defconfig
    # The base is everything of $d until the first '-'.
    diff -aur \
        toit/toolchains/$IDF_TARGET/sdkconfig.defaults \
        synthesized/$d/sdkconfig.defaults \
        > variants/$d/sdkconfig.defaults.patch
  fi;
done
