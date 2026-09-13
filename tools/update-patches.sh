#!/bin/bash
# Copyright (C) 2026 Toit contributors.
# Use of this source code is governed by a BSD0-style license that can be
# found in the LICENSE_BSD0 file.

set -eo pipefail

TOIT_EXEC=$1
shift

# Activate the tools and Python environment belonging to this Toit checkout.
TOIT_ROOT=toit
for arg in "$@"; do
  case "$arg" in
    --toit-root=*) TOIT_ROOT=${arg#*=} ;;
  esac
done
source "$TOIT_ROOT/third_party/esp-idf/export.sh"
exec "$TOIT_EXEC" run "$(dirname "$0")/main.toit" -- update-patches "$@"
