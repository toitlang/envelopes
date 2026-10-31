#!/usr/bin/env bash
# Copyright (C) 2026 Toit contributors.
# Use of this source code is governed by a BSD0-style license that can be
# found in the LICENSE_BSD0 file.

set -euo pipefail

toit_root=$1
cache_root=$2
version=$(tr -d '[:space:]' < "$toit_root/toolchains/ec618/base-version")
if [[ ! "$version" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid EC618 base version: $version" >&2
  exit 1
fi

if command -v sha256sum > /dev/null; then
  checksum=(sha256sum)
else
  checksum=(shasum --algorithm 256)
fi

mkdir -p "$cache_root"
cache_root=$(cd "$cache_root" && pwd)
tag="ec618-base-v$version"
base_dir="$cache_root/$tag"

if [[ ! -d "$base_dir" ]]; then
  staging=$(mktemp -d "$cache_root/.$tag.XXXXXX")
  trap 'rm -rf "$staging"' EXIT
  url="https://github.com/toitlang/toit/releases/download/$tag"
  echo "SDK requires published EC618 base $tag" >&2
  for suffix in .elf .bin .json -api.json -SHA256SUMS; do
    if ! curl --fail --silent --show-error --location --retry 3 \
        --output "$staging/$tag$suffix" "$url/$tag$suffix"; then
      echo "Failed to download required base artifact: $url/$tag$suffix" >&2
      echo "Use an SDK revision whose required base release is published, or publish $tag." >&2
      exit 1
    fi
  done
  (cd "$staging" && "${checksum[@]}" --check "$tag-SHA256SUMS") >&2

  # Use the names expected by the SDK without changing the verified files.
  ln -s "$tag.elf" "$staging/base.elf"
  ln -s "$tag.bin" "$staging/base.bin"
  ln -s "$tag.json" "$staging/base-manifest.json"
  ln -s "$tag-api.json" "$staging/base-api.json"
  mv "$staging" "$base_dir"
fi

# Recheck cached files too; never fall back to a locally rebuilt base.
(cd "$base_dir" && "${checksum[@]}" --check "$tag-SHA256SUMS") >&2
if [[ ! "$base_dir/base.elf" -ef "$base_dir/$tag.elf" ||
      ! "$base_dir/base.bin" -ef "$base_dir/$tag.bin" ||
      ! "$base_dir/base-manifest.json" -ef "$base_dir/$tag.json" ||
      ! "$base_dir/base-api.json" -ef "$base_dir/$tag-api.json" ]]; then
  echo "Invalid cached EC618 base aliases in $base_dir" >&2
  exit 1
fi
printf '%s\n' "$base_dir"
