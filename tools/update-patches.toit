// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a BSD0-style license that can be
// found in the LICENSE_BSD0 file.

import encoding.json
import host.directory
import host.file
import host.pipe
import .utils

read-text path/string -> string:
  return (file.read-content path).to-string

read-optional path/string -> string?:
  return file.is-file path ? (read-text path) : null

run-command arguments/List --environment/Map?=null --log/string?=null --allow-difference/bool=false -> string:
  stream := pipe.OpenPipe false
  status := null
  output := ""
  try:
    // The shell combines the output streams; command arguments stay separate.
    command := ["bash", "-c", "exec \"\$@\" 2>&1", "update-patches"] + arguments
    child := pipe.fork true pipe.PIPE-INHERITED stream.fd pipe.PIPE-INHERITED command.first command
        --environment=environment
    try:
      stream.in.buffer-all
      output = stream.in.read-string stream.in.buffered-size
    finally:
      status = pipe.wait-for child[3]
  finally:
    stream.close
  if log: file.write-content output --path=log
  code := pipe.exit-code status
  if code != 0 and not (allow-difference and code == 1):
    throw "Command failed: $arguments\n$output"
  return output

// Returns a setting pair, or null for a comment or blank line.
parse-setting_ line/string -> List?:
  line = line.trim --right "\r"
  if line.starts-with "CONFIG_" and line.contains "=":
    separator := line.index-of "="
    return [line[..separator], line[separator + 1..]]
  if line.starts-with "# CONFIG_" and line.ends-with " is not set":
    return [line[2..line.size - " is not set".size], "n"]
  if line.trim == "" or line.starts-with "#": return null
  throw "Unrecognized sdkconfig line: $line"

settings text/string -> Map:
  result := {:}
  (text.split "\n").do: | line/string |
    pair := parse-setting_ line
    if not pair: continue.do
    key := pair[0]
    if result.contains key: throw "Duplicate sdkconfig setting: $key"
    result[key] = pair[1]
  return result

class Migration:
  content/string
  changes/Map

  constructor .content .changes:

// Applies only variant differences, rejecting changes made by both sides.
migrate old-base/string old-variant/string new-base/string -> Migration:
  old := settings old-base
  variant := settings old-variant
  current := settings new-base
  changes := {:}
  keys := {}
  keys.add-all (old.keys + variant.keys)
  keys.do: | key/string |
    if (old.get key) != (variant.get key):
      changes[key] = variant.get key
  conflicts := []
  changes.do: | key/string value/string? |
    if (current.get key) != (old.get key) and (current.get key) != value:
      conflicts.add "$key: old base=$(old.get key), variant=$value, current base=$(current.get key)"
  if not conflicts.is-empty:
    throw "Conflicting configuration changes:\n$(conflicts.sort.join "\n")"

  merged := current.copy
  changes.do: | key value |
    if value:
      merged[key] = value
    else:
      merged.remove key
  return Migration (render-settings_ new-base merged variant.keys) changes

// Preserves SDK lines and places added options near their variant neighbors.
render-settings_ base/string desired/Map order/List -> string:
  current := settings base
  newline := base.contains "\r\n" ? "\r\n" : "\n"
  before := {:}
  following := ""
  order.do --reversed: | key/string |
    if current.contains key and desired.contains key:
      following = key
    else if desired.contains key and not current.contains key:
      (before.get following --init=: []).insert --at=0 "$key=$desired[key]$newline"
  lines := []
  // Split while retaining line endings, including a possible final bare line.
  start := 0
  while start < base.size:
    end := base.index-of "\n" start
    if end < 0: end = base.size
    line := base[start..end]
    end = min (end + 1) base.size
    original := base[start..end]
    start = end
    pair := parse-setting_ line
    if not pair:
      lines.add original
      continue
    key := pair[0]
    lines.add-all (before.get key or [])
    if desired.contains key:
      lines.add (desired[key] == current[key] ? original : "$key=$desired[key]$newline")
  trailing := before.get ""
  if trailing:
    if not lines.is-empty and not lines.last.ends-with "\n":
      lines[lines.size - 1] += newline
    lines.add-all trailing
  return lines.join ""

validate-effective effective/Map roundtrip/Map changes/Map:
  same := effective.size == roundtrip.size and (effective.every: | key value |
    roundtrip.contains key and (roundtrip.get key) == value)
  if not same:
    throw "The regenerated defaults change the effective configuration"
  changes.do: | key/string value/string? |
    // Removing a default lets Kconfig choose the value. Explicit variant
    // values must still take effect, including after dependency changes.
    if not value: continue.do
    expected := value == "y" ? true : value == "n" ? false : null
    if value.starts-with "\"":
      expected = json.decode value.to-byte-array
    else if value != "y" and value != "n":
      expected = int.parse value
    actual := effective.get (key["CONFIG_".size..])
    if actual != expected:
      throw "$key requested $value, but Kconfig produced $actual. Check symbol renames and dependencies."

class Variant_:
  name/string
  chip/string
  current/string
  migration/Migration

  constructor .name .chip .current .migration:

class Updater:
  toit-root/string
  variants-root/string
  sdk-path/string
  base/string

  constructor --toit-root/string --variants-root/string --sdk-path/string --base/string="":
    this.toit-root = toit-root
    this.variants-root = variants-root
    this.sdk-path = sdk-path
    this.base = base

  git arguments/List -> string:
    return run-command (["git", "-C", toit-root] + arguments)

  dirty -> bool:
    return (git ["status", "--porcelain", "--untracked-files=no", "--", "toolchains", "third_party/esp-idf"]) != ""

  update work/string [synthesize]:
    baseline := "$variants-root/sdkconfig.base"
    if base == "" and not file.is-file baseline:
      throw "Missing $baseline. Set PATCH_BASE to the Toit commit against which the patches were generated."
    before := base == "" ? (read-text baseline).trim : base
    target := (git ["rev-parse", "HEAD"]).trim
    before = (git ["rev-parse", "--verify", "$before^{commit}"]).trim
    if dirty: throw "Commit or stash Toit toolchain/ESP-IDF changes first"

    names := []
    entries := directory.DirectoryStream variants-root
    try:
      while name := entries.next:
        if file.is-file "$variants-root/$name/sdkconfig.defaults.patch": names.add name
    finally:
      entries.close
    names.sort --in-place
    if names.is-empty: throw "No sdkconfig.defaults.patch files in $variants-root"
    print "Migrating $names.size patches from $before to $target"

    staged-variants := "$work/variants"
    projects := "$work/synthesized"
    builds := "$work/build"
    originals := {baseline: read-optional baseline}
    variants := []
    // Reconstruct and merge every variant before running IDF configuration.
    names.do: | name/string |
      exception := catch:
        patch := "$variants-root/$name/sdkconfig.defaults.patch"
        originals[patch] = read-text patch
        chip := (name.split "-").first
        path := "toolchains/$chip/sdkconfig.defaults"
        old := git ["show", "$before:$path"]
        current := read-text "$toit-root/$path"
        staged := "$staged-variants/$name"
        copy-directory --from="$variants-root/$name/" --to="$staged/"
        defaults := "$staged/sdkconfig.defaults"
        if file.is-file "$staged/sdkconfig" or file.is-file defaults:
          throw "Variant contains both a config file and a defaults patch"
        file.write-content old --path=defaults
        run-command ["patch", "--batch", "--forward", "--fuzz=0", defaults, patch]
        migration := migrate old (read-text defaults) current
        file.write-content migration.content --path=defaults
        variants.add (Variant_ name chip current migration)
      if exception: throw "$name: $exception"

    synthesize.call staged-variants projects builds names

    replacements := {:}
    variants.do: | variant/Variant_ |
      name := variant.name
      project := "$projects/$name"
      print "Validating $name"
      exception := catch: normalize project "$builds/$name" variant.chip variant.migration.changes
      if exception: throw "$name: $exception"
      // Normalization must not introduce unrelated deletions into the patch.
      // Diff the migrated edits, preserving all other SDK assignments.
      original := "$project/base.defaults"
      migrated := "$project/migrated.defaults"
      file.write-content variant.current --path=original
      file.write-content variant.migration.content --path=migrated
      replacements["$variants-root/$name/sdkconfig.defaults.patch"] = run-command
          ["diff", "-u", "--label", "toit/toolchains/$variant.chip/sdkconfig.defaults",
           "--label", "synthesized/$name/sdkconfig.defaults", original, migrated]
          --allow-difference
    replacements[baseline] = "$target\n"

    // Do not overwrite edits made while IDF was running.
    if (git ["rev-parse", "HEAD"]).trim != target:
      throw "The Toit checkout changed while regenerating patches; retry the update"
    if dirty: throw "Toit toolchain/ESP-IDF files changed while regenerating patches"
    originals.do: | path/string original/string? |
      if (read-optional path) != original:
        throw "$path changed while regenerating patches; retry the update"
    replacements.do: | path/string content/string |
      if content != originals[path]: file.write-content content --path=path
    print "Updated $names.size patches and $baseline"

  normalize project/string build/string chip/string changes/Map:
    idf := "$toit-root/third_party/esp-idf"
    environment := {"IDF_TARGET": chip, "SDKCONFIG_DEFAULTS": null}
    run-command ["python", "$idf/tools/idf.py", "-C", project, "-B", build, "save-defconfig"]
        --environment=environment
        --log="$project/save-defconfig.log"
    effective := json.decode (file.read-content "$build/config/sdkconfig.json")
    // CMake sets this for Kconfig, but it is not included in config.env.
    if effective.contains "IDF_INIT_VERSION":
      environment["IDF_INIT_VERSION"] = effective["IDF_INIT_VERSION"]
    run-command
        ["python", "-m", "kconfgen", "--list-separator=semicolon",
         "--kconfig", "$idf/Kconfig", "--sdkconfig-rename", "$idf/sdkconfig.rename",
         "--env-file", "$build/config.env", "--config", "$project/roundtrip.sdkconfig",
         "--defaults", "$project/sdkconfig.defaults", "--dont-write-deprecated",
         "--output", "json", "$project/roundtrip.json"]
        --environment=environment
        --log="$project/roundtrip.log"
    validate-effective effective (json.decode (file.read-content "$project/roundtrip.json")) changes
