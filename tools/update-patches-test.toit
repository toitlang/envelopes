// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a BSD0-style license that can be
// found in the LICENSE_BSD0 file.

import expect show *
import host.directory
import host.file
import .update-patches as patches
import .utils

tests-run := 0

test name/string [block]:
  block.call
  tests-run++
  print "Passed: $name"

fails message/string [block]:
  error := catch: block.call
  expect-not-null error
  expect (error.stringify.contains message) --message="$error"

with-fixture [block]:
  root := directory.mkdtemp "/tmp/envelope-update-test-"
  try:
    block.call (Fixture root)
  finally:
    directory.rmdir --recursive root

main:
  test "Preserves upstream changes and variant additions/removals":
    result := patches.migrate
        "CONFIG_A=1\nCONFIG_B=y\nCONFIG_C=\"old\"\n"
        "CONFIG_A=2\nCONFIG_C=\"old\"\nCONFIG_D=y\n"
        "CONFIG_A=1\nCONFIG_B=y\nCONFIG_C=\"new\"\nCONFIG_E=3\n"
    expect-structural-equals {"CONFIG_A": "2", "CONFIG_C": "\"new\"", "CONFIG_D": "y", "CONFIG_E": "3"}
        patches.settings result.content
  test "Rejects conflicting edits and deletions":
    ["CONFIG_A=2\n", ""].do: | variant/string |
      fails "CONFIG_A: old base=1":
        patches.migrate "CONFIG_A=1\n" variant "CONFIG_A=3\n"
  test "Accepts matching upstream changes":
    expect-equals "CONFIG_A=2\n" (patches.migrate "CONFIG_A=1\n" "CONFIG_A=2\n" "CONFIG_A=2\n").content
  test "Does not resurrect upstream removals":
    expect-equals "CONFIG_B=y\n" (patches.migrate "CONFIG_A=y\n" "CONFIG_A=y\nCONFIG_B=y\n" "").content
  test "Accepts equivalent disabled notation":
    expect-structural-equals {:}
        (patches.migrate "CONFIG_A=n\n" "# CONFIG_A is not set\n" "CONFIG_A=y\n").changes
  test "Rejects duplicate settings":
    fails "Duplicate": patches.settings "CONFIG_A=y\n# CONFIG_A is not set\n"
  test "Preserves comments and explicit SDK defaults":
    old := "# SDK defaults\nCONFIG_A=y\n# CONFIG_B is not set\n"
    variant := "# SDK defaults\nCONFIG_FEATURE=y\nCONFIG_A=y\n# CONFIG_B is not set\n"
    result := patches.migrate old variant (old + "CONFIG_SPI_MASTER_ISR_IN_IRAM=y\n")
    expect-equals (variant + "CONFIG_SPI_MASTER_ISR_IN_IRAM=y\n") result.content
    expect-structural-equals {"CONFIG_FEATURE": "y"} result.changes
  test "Preserves checkout line endings":
    result := patches.migrate "CONFIG_A=y\n" "CONFIG_A=y\nCONFIG_FEATURE=y\n"
        "# SDK\r\nCONFIG_A=y\r\nCONFIG_NEW=y\r\n"
    expect-equals "# SDK\r\nCONFIG_A=y\r\nCONFIG_NEW=y\r\nCONFIG_FEATURE=y\r\n" result.content
  test "Migrates patches and supports repeated updates":
    with-fixture: | f/Fixture |
      f.update
      first := f.snapshot
      f.update
      expect-structural-equals first f.snapshot
      expect-equals f.after (patches.read-text "$f.variants/sdkconfig.base").trim
      f.names.do: | name/string |
        result := "$f.root/result"
        file.write-content (patches.read-text f.basefile) --path=result
        patches.run-command ["patch", "--batch", "--fuzz=0", result, "$f.variants/$name/sdkconfig.defaults.patch"]
        expect-equals "CONFIG_UPSTREAM=3\nCONFIG_VARIANT=2\n" (patches.read-text result)
  test "A late validation failure keeps every original":
    with-fixture: | f/Fixture |
      before := f.snapshot
      f.updater.mode = "fail"
      fails "esp32-b: IDF failed": f.update
      expect-structural-equals before f.snapshot
  test "A synthesis failure keeps every original":
    with-fixture: | f/Fixture |
      before := f.snapshot
      fails "Synthesis failed":
        f.updater.update (directory.mkdtemp "$f.root/work-"): | staged projects builds variants |
          throw "Synthesis failed"
      expect-equals 0 f.updater.calls
      expect-structural-equals before f.snapshot
  test "Normalization omissions do not become variant edits":
    with-fixture: | f/Fixture |
      f.updater.mode = "normalize"
      f.update
      f.names.do: | name/string |
        patch := patches.read-text "$f.variants/$name/sdkconfig.defaults.patch"
        expect-not (patch.contains "-CONFIG_UPSTREAM")
        expect (patch.contains " CONFIG_UPSTREAM=3")
  test "An upstream-absorbed variant can be updated again":
    with-fixture: | f/Fixture |
      file.write-content "CONFIG_UPSTREAM=3\nCONFIG_VARIANT=2\n" --path=f.basefile
      f.git ["commit", "-qam", "Adopt variant setting upstream"]
      f.update
      f.names.do: | name/string |
        expect-equals "" (patches.read-text "$f.variants/$name/sdkconfig.defaults.patch")
      f.update
  test "A bad patch leaves every original unchanged":
    with-fixture: | f/Fixture |
      patch := "$f.variants/esp32-b/sdkconfig.defaults.patch"
      content := (patches.read-text patch).replace "-CONFIG_VARIANT=1" "-CONFIG_VARIANT=99"
      file.write-content content --path=patch
      before := f.snapshot
      fails "Command failed": f.update
      expect-equals 0 f.updater.calls
      expect-structural-equals before f.snapshot
  test "Base override bootstraps a missing baseline":
    with-fixture: | f/Fixture |
      file.delete "$f.variants/sdkconfig.base"
      f.updater = TestUpdater f.toit f.variants "$f.root/sdk" --base=f.before
      f.update
      expect-equals f.after (patches.read-text "$f.variants/sdkconfig.base").trim
  test "Missing baseline explains the override":
    with-fixture: | f/Fixture |
      file.delete "$f.variants/sdkconfig.base"
      fails "Set PATCH_BASE": f.update
  test "Rejects uncommitted target defaults":
    with-fixture: | f/Fixture |
      file.write-content "CONFIG_UPSTREAM=99\n" --path=f.basefile
      before := f.snapshot
      fails "Commit or stash": f.update
      expect-structural-equals before f.snapshot
  test "Rejects target changes during generation":
    with-fixture: | f/Fixture |
      before := f.snapshot
      f.updater.mode = "edit-toit"
      fails "files changed while regenerating": f.update
      expect-structural-equals before f.snapshot
  test "Preserves concurrent patch edits":
    with-fixture: | f/Fixture |
      f.updater.mode = "edit-patch"
      fails "changed while regenerating": f.update
      expect-equals "user edit\n" (patches.read-text "$f.variants/esp32-a/sdkconfig.defaults.patch")
      expect-equals f.before (patches.read-text "$f.variants/sdkconfig.base").trim
  test "Validates booleans, strings, numbers and default removals":
    effective := {"FEATURE": true, "DISABLED": false, "NAME": "toit", "SIZE": 16}
    patches.validate-effective effective effective.copy
        {"CONFIG_FEATURE": "y", "CONFIG_DISABLED": "n", "CONFIG_NAME": "\"toit\"",
         "CONFIG_SIZE": "0x10", "CONFIG_REMOVED": null}
  test "Rejects ignored variant settings":
    fails "CONFIG_FEATURE requested y":
      patches.validate-effective {"FEATURE": false} {"FEATURE": false} {"CONFIG_FEATURE": "y"}
  test "Rejects lossy defaults":
    fails "effective configuration":
      patches.validate-effective {"FEATURE": true} {"FEATURE": false} {:}
  test "Captures child stderr and rejects unsuccessful commands":
    expect-equals "out\nerr\n" (patches.run-command ["sh", "-c", "echo out; echo err >&2"])
    fails "failure details": patches.run-command ["sh", "-c", "echo 'failure details' >&2; exit 2"]
  test "Passes command arguments literally":
    expect-equals "spaces; 'quotes'" (patches.run-command ["printf", "%s", "spaces; 'quotes'"])
  print "$tests-run tests passed"

class Fixture:
  root/string
  toit/string
  variants/string
  basefile/string
  before/string := ""
  after/string := ""
  updater/TestUpdater := ?
  names ::= ["esp32-a", "esp32-b"]

  constructor .root:
    toit = "$root/toit"
    variants = "$root/variants"
    basefile = "$toit/toolchains/esp32/sdkconfig.defaults"
    updater = TestUpdater toit variants "$root/sdk"
    directory.mkdir --recursive "$toit/toolchains/esp32"
    git ["init", "-q"]
    git ["config", "user.email", "test@example.com"]
    git ["config", "user.name", "Test"]
    old := "CONFIG_UPSTREAM=1\nCONFIG_VARIANT=1\n"
    file.write-content old --path=basefile
    git ["add", "."]
    git ["commit", "-qm", "Old defaults"]
    before = (git ["rev-parse", "HEAD"]).trim
    directory.mkdir variants
    file.write-content "$before\n" --path="$variants/sdkconfig.base"
    file.write-content "CONFIG_UPSTREAM=1\nCONFIG_VARIANT=2\n" --path="$root/variant"
    patch := patches.run-command ["diff", "-u", "--label", "old", "--label", "variant", basefile, "$root/variant"]
        --allow-difference
    names.do: | name/string |
      directory.mkdir "$variants/$name"
      file.write-content patch --path="$variants/$name/sdkconfig.defaults.patch"
    file.write-content "CONFIG_UPSTREAM=3\nCONFIG_VARIANT=1\n" --path=basefile
    git ["commit", "-qam", "New defaults"]
    after = (git ["rev-parse", "HEAD"]).trim

  git arguments/List -> string:
    return patches.run-command (["git", "-C", toit] + arguments)

  update:
    work := directory.mkdtemp "$root/work-"
    updater.update work: | staged projects builds variants |
      copy-directory --from="$staged/" --to="$projects/"

  snapshot -> Map:
    result := {"sdkconfig.base": patches.read-optional "$variants/sdkconfig.base"}
    names.do: | name/string |
      result[name] = patches.read-text "$variants/$name/sdkconfig.defaults.patch"
    return result

class TestUpdater extends patches.Updater:
  mode/string := ""
  calls/int := 0

  constructor toit/string variants/string sdk/string --base/string="":
    super --toit-root=toit --variants-root=variants --sdk-path=sdk --base=base

  normalize project/string build/string chip/string changes/Map:
    calls++
    if mode == "fail" and calls == 2: throw "IDF failed"
    if mode == "normalize":
      file.write-content "CONFIG_VARIANT=2\n" --path="$project/sdkconfig.defaults"
    if mode == "edit-toit":
      file.write-content "CONFIG_UPSTREAM=99\n" --path="$toit-root/toolchains/esp32/sdkconfig.defaults"
    if mode == "edit-patch":
      file.write-content "user edit\n" --path="$variants-root/esp32-a/sdkconfig.defaults.patch"
