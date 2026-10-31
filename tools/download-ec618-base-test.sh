#!/usr/bin/env bash
# Copyright (C) 2026 Toit contributors.
# Use of this source code is governed by a BSD0-style license that can be
# found in the LICENSE_BSD0 file.

set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export EC618_TEST_RELEASE="$work/release"
export EC618_TEST_REQUESTS="$work/requests"
mkdir -p "$work/toit/toolchains/ec618" "$work/toit/tools" "$work/bin" "$EC618_TEST_RELEASE"
echo 5 > "$work/toit/toolchains/ec618/base-version"
tag=ec618-base-v5
for suffix in .elf .bin .json -api.json; do
  echo "Released $tag$suffix" > "$EC618_TEST_RELEASE/$tag$suffix"
done
(cd "$EC618_TEST_RELEASE" && sha256sum "$tag.elf" "$tag.bin" "$tag.json" "$tag-api.json" > "$tag-SHA256SUMS")

cat > "$work/bin/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
while [[ "$1" != --output ]]; do shift; done
output=$2
url=$3
echo "$url" >> "$EC618_TEST_REQUESTS"
[[ "$url" == "https://github.com/toitlang/toit/releases/download/ec618-base-v5/"* ]]
cp "$EC618_TEST_RELEASE/${url##*/}" "$output"
CURL
chmod +x "$work/bin/curl"
export PATH="$work/bin:$PATH"

cat > "$work/bin/toit-sdk" <<'TOIT'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == pkg && "$2" == install && "$3" == "--project-root="* ]]
[[ "${EC618_TEST_INSTALL_FAIL:-0}" != 1 ]]
project=${3#--project-root=}
[[ "$project" == */toit/tools ]]
mkdir -p "$project/.packages"
touch "$project/.packages/installed"
TOIT
chmod +x "$work/bin/toit-sdk"

cat > "$work/toit/Makefile" <<'MAKE'
.PHONY: host-tools ec618 ec618-base
host-tools:
	@mkdir -p "$(BUILD)/host/sdk/bin"
	@cp "$(EC618_TEST_RELEASE)/../bin/toit-sdk" "$(BUILD)/host/sdk/bin/toit"
ec618:
	@test -n "$(EC618_BASE_DIR)"
	@test -f "$(CURDIR)/tools/.packages/installed"
	@cmp "$(EC618_BASE_DIR)/base.elf" "$(EC618_TEST_RELEASE)/ec618-base-v5.elf"
	@cmp "$(EC618_BASE_DIR)/base.bin" "$(EC618_TEST_RELEASE)/ec618-base-v5.bin"
	@touch "$(BUILD)/built"
ec618-base:
	@echo "The base must never be rebuilt" >&2
	@exit 99
MAKE

build() {
  make --no-print-directory build-ec618 TOIT_DIRECTORY="$work/toit" BUILD_DIRECTORY="$work/build"
}

reject_build() {
  rm -f "$work/build/built"
  if build > "$work/rejected.log" 2>&1; then
    echo "Expected the build to fail" >&2
    exit 1
  fi
  test ! -e "$work/build/built"
}

build
test -f "$work/build/built"
test "$(wc -l < "$EC618_TEST_REQUESTS")" -eq 5
echo "Passed: builds slots against the SDK-selected released base"

build
test "$(wc -l < "$EC618_TEST_REQUESTS")" -eq 5
echo "Passed: reuses verified cached artifacts"

rm -rf "$work/toit/tools/.packages"
export EC618_TEST_INSTALL_FAIL=1
reject_build
test ! -e "$work/toit/tools/.packages/installed"
unset EC618_TEST_INSTALL_FAIL
echo "Passed: package installation failures stop the slot build"

build
test -f "$work/toit/tools/.packages/installed"
test -f "$work/build/built"
echo "Passed: installs SDK tool packages before building slots"

cache="$work/build/ec618-bases/$tag"
echo corrupted >> "$cache/$tag.bin"
reject_build
echo "Passed: corrupt cached base stops the build"
cp "$EC618_TEST_RELEASE/$tag.bin" "$cache/$tag.bin"

rm "$cache/base.elf"
reject_build
echo "Passed: missing base ELF alias stops the build before SDK fallback"
ln -s "$tag.elf" "$cache/base.elf"

echo 6 > "$work/toit/toolchains/ec618/base-version"
reject_build
test ! -d "$work/build/ec618-bases/ec618-base-v6"
grep -q 'SDK requires published EC618 base ec618-base-v6' "$work/rejected.log"
grep -q 'Failed to download required base artifact: https://github.com/toitlang/toit/releases/download/ec618-base-v6/ec618-base-v6.elf' "$work/rejected.log"
echo "Passed: an unavailable SDK-selected release cannot use an older base"

echo 5 > "$work/toit/toolchains/ec618/base-version"
rm -rf "$cache"
echo corrupted >> "$EC618_TEST_RELEASE/$tag.bin"
reject_build
test ! -d "$cache"
echo "Passed: corrupt downloads are not cached or built"

echo invalid > "$work/toit/toolchains/ec618/base-version"
reject_build
echo "Passed: invalid base versions stop the build"
