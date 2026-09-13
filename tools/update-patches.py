#!/usr/bin/env python3
# Copyright (C) 2026 Toit contributors.
# Use of this source code is governed by a BSD0-style license that can be
# found in the LICENSE_BSD0 file.

"""Migrate variant configuration changes onto the checked-out Toit defaults."""

import argparse
import difflib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


class UpdateError(Exception):
    pass


def run(args, *, env=None, log=None):
    result = subprocess.run(args, env=env, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    if log is not None:
        log.write_text(result.stdout)
    if result.returncode:
        raise UpdateError(f"Command failed: {args}\n{result.stdout}")
    return result.stdout


def settings(text):
    result = {}
    for line in text.splitlines():
        match = re.fullmatch(r"(CONFIG_\w+)=(.*)", line)
        disabled = re.fullmatch(r"# (CONFIG_\w+) is not set", line)
        if match:
            key, value = match.groups()
        elif disabled:
            key, value = disabled[1], "n"
        elif not line.strip() or line.startswith("#"):
            continue
        else:
            raise UpdateError(f"Unrecognized sdkconfig line: {line}")
        if key in result:
            raise UpdateError(f"Duplicate sdkconfig setting: {key}")
        result[key] = value
    return result


def migrate(old_base, old_variant, new_base):
    """Apply only variant differences, rejecting changes made by both sides."""
    old, variant, current = map(settings, (old_base, old_variant, new_base))
    changes = {key: variant.get(key) for key in old.keys() | variant.keys()
               if old.get(key) != variant.get(key)}
    conflicts = []
    for key, value in changes.items():
        if current.get(key) not in (old.get(key), value):
            conflicts.append(f"{key}: old base={old.get(key)!r}, "
                             f"variant={value!r}, current base={current.get(key)!r}")
    if conflicts:
        raise UpdateError("Conflicting configuration changes:\n" +
                          "\n".join(sorted(conflicts)))

    merged = dict(current)
    for key in current.keys() | old.keys():
        if key in changes:
            if changes[key] is None:
                merged.pop(key, None)
            else:
                merged[key] = changes[key]
    # Preserve the variant's ordering for options newly added to the base.
    for key, value in variant.items():
        if key in changes and key not in merged:
            merged[key] = value
    return render_settings(new_base, merged, variant), changes


def render_settings(base, desired, order):
    """Preserve SDK lines and place added options near their variant neighbors."""
    current = settings(base)
    before = {}
    following = None
    for key in reversed(order):
        if key in current and key in desired:
            following = key
        elif key in desired and key not in current:
            before.setdefault(following, []).insert(0, f"{key}={desired[key]}\n")
    lines = []
    for line in base.splitlines(True):
        key = next(iter(settings(line)), None)
        if key is None:
            lines.append(line)
        else:
            lines.extend(before.pop(key, []))
            if key in desired:
                lines.append(line if desired[key] == current[key] else f"{key}={desired[key]}\n")
    if before.get(None):
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"
        lines.extend(before.pop(None))
    return "".join(lines)


def normalize(project, build, idf, chip, changes):
    env = dict(os.environ, IDF_TARGET=chip)
    # Ignore defaults inherited from a caller's unrelated ESP-IDF project.
    env.pop("SDKCONFIG_DEFAULTS", None)
    run([sys.executable, str(idf / "tools/idf.py"), "-C", str(project),
         "-B", str(build), "save-defconfig"], env=env,
        log=project / "save-defconfig.log")
    effective = json.loads((build / "config/sdkconfig.json").read_text())
    # CMake sets this for Kconfig, but it is not included in config.env.
    if "IDF_INIT_VERSION" in effective:
        env["IDF_INIT_VERSION"] = effective["IDF_INIT_VERSION"]

    # Reload the minimal defaults from scratch through the same Kconfig inputs.
    run([sys.executable, "-m", "kconfgen", "--list-separator=semicolon",
         "--kconfig", str(idf / "Kconfig"),
         "--sdkconfig-rename", str(idf / "sdkconfig.rename"),
         "--env-file", str(build / "config.env"),
         "--config", str(project / "roundtrip.sdkconfig"),
         "--defaults", str(project / "sdkconfig.defaults"),
         "--dont-write-deprecated", "--output", "json",
         str(project / "roundtrip.json")], env=env,
        log=project / "roundtrip.log")
    if effective != json.loads((project / "roundtrip.json").read_text()):
        raise UpdateError("The regenerated defaults change the effective configuration")
    for key, value in sorted(changes.items()):
        # Removing a default lets Kconfig choose the value. Explicit variant
        # values must still take effect; changed dependencies or renamed/removed
        # symbols need attention rather than silently dropping them.
        if value is None:
            continue
        if value in ("y", "n"):
            expected = value == "y"
        elif value.startswith('"'):
            expected = json.loads(value)
        else:
            expected = int(value, 16 if value.lower().startswith("0x") else 10)
        actual = effective.get(key.removeprefix("CONFIG_"))
        if actual != expected:
            raise UpdateError(f"{key} requested {value}, but Kconfig produced {actual!r}. "
                              "Check symbol renames and dependencies.")


def update(args, work):
    toit = args.toit_root.resolve()
    variants = args.variants_root.resolve()
    baseline = variants / "sdkconfig.base"
    if not args.base and not baseline.is_file():
        raise UpdateError(f"Missing {baseline}. Set PATCH_BASE to the Toit commit "
                          "against which the patches were generated.")
    base = args.base or baseline.read_text().strip()
    target = run(["git", "-C", str(toit), "rev-parse", "HEAD"]).strip()
    base = run(["git", "-C", str(toit), "rev-parse", "--verify",
                f"{base}^{{commit}}"]).strip()
    # The recorded target must reproduce the defaults and Kconfig used here.
    dirty = run(["git", "-C", str(toit), "status", "--porcelain",
                 "--untracked-files=no", "--", "toolchains", "third_party/esp-idf"])
    if dirty:
        raise UpdateError("Commit or stash Toit toolchain/ESP-IDF changes first:\n" + dirty)

    patches = sorted(variants.glob("*/sdkconfig.defaults.patch"))
    if not patches:
        raise UpdateError(f"No sdkconfig.defaults.patch files in {variants}")
    print(f"Migrating {len(patches)} patches from {base[:12]} to {target[:12]}", flush=True)
    staged_variants = work / "variants"
    projects = work / "synthesized"
    builds = work / "build"
    originals = {baseline: baseline.read_bytes() if baseline.exists() else None}
    configs = {}

    # Reconstruct and merge every variant before running any IDF configuration.
    for patch in patches:
        name = patch.parent.name
        chip = name.split("-", 1)[0]
        try:
            originals[patch] = patch.read_bytes()
            path = f"toolchains/{chip}/sdkconfig.defaults"
            old = run(["git", "-C", str(toit), "show", f"{base}:{path}"])
            current = (toit / path).read_text()
            staged = staged_variants / name
            shutil.copytree(patch.parent, staged)
            if (staged / "sdkconfig").exists() or (staged / "sdkconfig.defaults").exists():
                raise UpdateError("Variant contains both a config file and a defaults patch")
            defaults = staged / "sdkconfig.defaults"
            defaults.write_text(old)
            run(["patch", "--batch", "--forward", "--fuzz=0", str(defaults), str(patch)])
            merged, changes = migrate(old, defaults.read_text(), current)
            defaults.write_text(merged)
            configs[name] = (chip, current, changes, merged)
        except UpdateError as error:
            raise UpdateError(f"{name}: {error}") from error

    run([args.toit_exec, "run", str(Path(__file__).with_name("main.toit")), "--",
         "synthesize", f"--toit-root={toit}", f"--build-root={builds}",
         f"--output-root={projects}", f"--sdk-path={args.sdk_path.resolve()}",
         f"--variants-root={staged_variants}", *configs], log=work / "synthesize.log")

    replacements = {}
    for name, (chip, current, changes, merged) in configs.items():
        print(f"Regenerating {name}", flush=True)
        project = projects / name
        try:
            normalize(project, builds / name, toit / "third_party/esp-idf", chip, changes)
        except UpdateError as error:
            raise UpdateError(f"{name}: {error}") from error
        patch = variants / name / "sdkconfig.defaults.patch"
        # save-defconfig omits redundant SDK assignments. That is useful for
        # validation, but must not introduce unrelated deletions into a variant
        # patch. Only the migrated original variant edits belong in the patch.
        replacements[patch] = "".join(difflib.unified_diff(
            current.splitlines(True), merged.splitlines(True),
            fromfile=f"toit/toolchains/{chip}/sdkconfig.defaults",
            tofile=f"synthesized/{name}/sdkconfig.defaults")).encode()
    replacements[baseline] = (target + "\n").encode()

    # Do not overwrite edits made while IDF was running.
    if run(["git", "-C", str(toit), "rev-parse", "HEAD"]).strip() != target:
        raise UpdateError("The Toit checkout changed while regenerating patches; retry the update")
    if run(["git", "-C", str(toit), "status", "--porcelain", "--untracked-files=no",
            "--", "toolchains", "third_party/esp-idf"]):
        raise UpdateError("Toit toolchain/ESP-IDF files changed while regenerating patches")
    for path, original in originals.items():
        if (path.read_bytes() if path.exists() else None) != original:
            raise UpdateError(f"{path} changed while regenerating patches; retry the update")
    for path, content in replacements.items():
        if content != originals[path]:
            path.write_bytes(content)
    print(f"Updated {len(patches)} patches and {baseline}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toit-root", type=Path, default=Path("toit"))
    parser.add_argument("--variants-root", type=Path, default=Path("variants"))
    parser.add_argument("--build-root", type=Path, default=Path("build"))
    parser.add_argument("--sdk-path", type=Path, default=Path("build/host/sdk"))
    parser.add_argument("--toit-exec", default="toit")
    parser.add_argument("--base", default="", help="Override variants/sdkconfig.base")
    args = parser.parse_args()
    args.build_root.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="update-patches-", dir=args.build_root.resolve()))
    try:
        update(args, work)
    except (UpdateError, OSError, ValueError) as error:
        print(f"Patch update failed: {error}\nWorking files and logs: {work}", file=sys.stderr)
        return 1
    shutil.rmtree(work)
    return 0


if __name__ == "__main__":
    sys.exit(main())
