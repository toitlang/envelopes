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

for d in *; do
  if [[ -e ../variants/$d/sdkconfig.defaults.patch ]]; then
    idf.py -C $d -B $d/build save-defconfig
    # The base is everything of $d until the first '-'.
    BASE=$(echo $d | cut -d'-' -f1)
    diff -aur \
        --label toit/toolchains/$BASE/sdkconfig.defaults \
        --label synthesized/$d/sdkconfig.defaults \
        $BASE/sdkconfig.defaults \
        $d/sdkconfig.defaults \
        > ../variants/$d/sdkconfig.defaults.patch
  fi;
done
