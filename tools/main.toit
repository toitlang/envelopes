// Copyright (C) 2023 Toitware ApS.
// Use of this from code is governed by an MIT-style license that can be
// found in the LICENSE_MIT file.

import cli
import fs
import host.file
import host.directory
import host.pipe
import writer show Writer
import .gist as gist
import .utils

GIT-URL ::= "https://github.com/toitlang/toit.git"
TOIT-IDF-COMPONENT-PATH ::= "toolchains/idf/components"

toit-partition-path-for_ --chip/string -> string:
  return "toolchains/$chip/partitions.csv"
toit-sdk-config-path-for_ --chip/string -> string:
  return "toolchains/$chip/sdkconfig"
toit-sdk-config-defaults-path-for_ --chip/string -> string:
  return "toolchains/$chip/sdkconfig.defaults"
toit-main-path-for_ --chip/string -> string:
  return "toolchains/$chip/main"

main args:
  ui := Ui_
  root-cmd := cli.Command "root"

  variant-list-cmd := cli.Command "list"
      --help="List all variants."
      --rest=[
        cli.Option "root"
            --help="The root directory to list variants from."
            --default="variants",
      ]
      --run=:: variant-list it --ui=ui
  root-cmd.add variant-list-cmd

  variant-synthesize-cmd := cli.Command "synthesize"
      --help="""
        Synthesize the given variants.

        Generates a project that can be compiled for each variant.

        For each variant creates a variant directory in the output root.
        For each variant defines the build directory as 'build-root/variant'.
        """
      --options=[
        cli.Option "output-root"
            --short-name="o"
            --help="The output directory to synthesize the variants to.",
        cli.Option "toit-root"
            --help="The root directory of the Toit SDK."
            --required,
        cli.Option "build-root"
            --help="The output directory for the compilation."
            --required,
        cli.Option "sdk-path"
            --help="The path to the Toit SDK. Typically in build/host/sdk."
            --required,
        cli.Option "variants-root"
            --help="The root directory of the variants."
            --required,
        cli.Flag "ignore-errors"
            --help="Ignore errors when synthesizing variants."
            --default=false,
        cli.Flag "update-patches"
            --help="Update the patches in the variants."
            --default=false
            --hidden,
      ]
      --rest=[
          cli.Option "variant"
              --help="The variant to synthesize."
              --required
              --multi,
      ]
      --run=:: variant-synthesize it --ui=ui
      --examples=[
        cli.Example """
            Synthesize variant 'variants/esp32-qemu' into 'synthesized/esp32-qemu', with
            Toit checked out in the 'toit' directory, the build directory set to 'build',
            and the SDK path set to 'build/host/sdk':"""
            --global-priority=1
            --arguments="--toit-root=toit --build-root=build --output-root=synthesized --sdk-path=build/host/sdk --variants-root=variants esp32-qemu"
      ]
  root-cmd.add variant-synthesize-cmd

  download-gist-cmd := cli.Command "download-gist"
      --help="Download all files of the given gist URL."
      --options=[
        cli.Option "output"
            --short-name="o"
            --help="The output directory to download the gist to."
            --required,
      ]
      --rest=[
          cli.Option "gist-url"
              --help="The URL of the gist to download."
              --required,
      ]
      --run=:: download-gist it --ui=ui
  root-cmd.add download-gist-cmd

  root-cmd.run args --ui=ui

variant-list parsed/cli.Parsed --ui/cli.Ui:
  root := parsed["root"]
  variants := variant-list --root=root --ui=ui
  variants.do: ui.print it

variant-list --root/string --ui/cli.Ui -> List:
  result := []

  variant-stream := directory.DirectoryStream root
  while variant := variant-stream.next:
    // First level of directory entries are the chips.
    if not file.is-directory "$root/$variant":
      // Skip over files like "README.md".
      continue

    result.add variant
  variant-stream.close
  return result

download-gist parsed/cli.Parsed --ui/cli.Ui:
  output := parsed["output"]
  gist-url := parsed["gist-url"]
  gist.download --output=output --gist-url=gist-url --ui=ui

variant-synthesize parsed/cli.Parsed --ui/cli.Ui:
  toit-root := parsed["toit-root"]
  output-root := parsed["output-root"]
  build-root := parsed["build-root"]
  sdk-path := parsed["sdk-path"]
  variants-root := parsed["variants-root"]
  variants := parsed["variant"]
  ignore-errors := parsed["ignore-errors"]
  update-patches := parsed["update-patches"]

  variants.do: | variant/string |
    exception := catch:
      variant-synthesize
          --variant-path="$variants-root/$variant"
          --toit-root=toit-root
          --output="$output-root/$variant"
          --build-path="$build-root/$variant"
          --sdk-path=sdk-path
          --update-patches=update-patches
          --ui=ui
    if exception:
      ui.print "Failed to synthesize variant '$variant': $exception."
      if not ignore-errors: ui.abort
      catch:
        directory.mkdir --recursive "$output-root/$variant"
        file.write-content --path="$output-root/$variant/failed" "$exception"


variant-synthesize
    --variant-path/string
    --toit-root/string
    --output/string
    --build-path/string
    --sdk-path/string
    --update-patches/bool
    --ui/cli.Ui:
  if file.is-file output:
    ui.print "Output is a file."
    ui.abort

  copy-directory --from="$variant-path/" --to="$output/"

  chip-variant := extract-chip-variant_ variant-path --ui=ui
  chip := chip-variant[0]

  ensure-main_ output --toit-root=toit-root --chip=chip
  ensure-partitions_ output --toit-root=toit-root --chip=chip
  ensure-sdkconfig_ output --toit-root=toit-root --chip=chip --ui=ui
  create-cmakelists_
      output
      --toit-root=toit-root
      --sdk-path=sdk-path
      --chip=chip
      --ui=ui

  create-makefile_
      output
      --toit-root=toit-root
      --build-path=build-path
      --chip=chip
      --ui=ui

  if update-patches:
    if file.is-file "$variant-path/partitions.csv.patch":
      original := "$toit-root/$(toit-partition-path-for_ --chip=chip)"
      patched := "$output/partitions.csv"
      update-patch_
          --from=original
          --to=patched
          --output="$variant-path/partitions.csv.patch"
          --ui=ui

    if file.is-file "$variant-path/sdkconfig.defaults.patch":
      original := "$toit-root/$(toit-sdk-config-defaults-path-for_ --chip=chip)"
      patched := "$output/sdkconfig.defaults"
      update-patch_
          --from=original
          --to=patched
          --output="$variant-path/sdkconfig.defaults.patch"
          --ui=ui

    if file.is-file "$variant-path/main.patch":
      original := "$toit-root/$(toit-main-path-for_ --chip=chip)"
      patched := "$output/main"
      update-patch_
          --from=original
          --to=patched
          --output="$variant-path/main.patch"
          --ui=ui

apply-directory-patch_ --patch-path/string --directory/string --strip/int=1:
  patch := file.read-content patch-path
  args := ["patch", "-d", directory]
  if strip > 0:
    args.add "-p$strip"
  stream := pipe.to args
  stream.out.write patch
  stream.close

// Same as $pipe.from but doesn't throw if the exit code is non-zero.
pipe-from arguments/List:
  pipe-ends := pipe.OpenPipe false --child-process-name=arguments[0]
  stdout := pipe-ends.fd
  pipes := pipe.fork true pipe.PIPE-INHERITED stdout pipe.PIPE-INHERITED arguments[0] arguments
  return pipe-ends

apply-file-patch_ --patch-path/string --file-path/string:
  patch := file.read-content patch-path
  args := ["patch", file-path]
  stream := pipe.to args
  stream.out.write patch
  stream.close

update-patch_ --from/string --to/string --output/string --ui/cli.Ui:
  ui.print "Updating $output."
  file.delete output
  // Use labels to avoid the timestamp.
  args := ["diff", "-aur", "--label", from, "--label", to, from, to]
  stream := pipe-from args
  out-stream := file.Stream.for-write output
  writer := out-stream.out
  while chunk := stream.read:
    writer.write chunk
  out-stream.close

ensure-main_ dir/string --toit-root/string --chip/string:
  if file.is-directory "$dir/main": return
  main-path := toit-main-path-for_ --chip=chip
  copy-directory --from="$toit-root/$main-path" --to="$dir/main"
  if file.is-file "$dir/main.patch":
    apply-directory-patch_ --patch-path="$dir/main.patch" --directory=dir

ensure-partitions_ dir/string --toit-root/string --chip/string:
  if file.is-file "$dir/partitions.csv": return
  partition-path := toit-partition-path-for_ --chip=chip
  copy-file --from="$toit-root/$partition-path" --to="$dir/partitions.csv"
  if file.is-file "$dir/partitions.csv.patch":
    apply-file-patch_ --patch-path="$dir/partitions.csv.patch" --file-path="$dir/partitions.csv"

ensure-sdkconfig_ dir/string --toit-root/string --chip/string --ui/cli.Ui:
  if file.is-file "$dir/sdkconfig" or file.is-file "$dir/sdkconfig.defaults": return

  if file.is-file "$dir/sdkconfig.patch":
    ui.print "Variants should only patch sdkconfig.defaults, not sdkconfig."
    ui.abort

  sdk-config-defaults-path := toit-sdk-config-defaults-path-for_ --chip=chip

  if file.is-file "$toit-root/$sdk-config-defaults-path":
    copy-file --from="$toit-root/$sdk-config-defaults-path" --to="$dir/sdkconfig.defaults"
    if file.is-file "$dir/sdkconfig.defaults.patch":
      apply-file-patch_ --patch-path="$dir/sdkconfig.defaults.patch" --file-path="$dir/sdkconfig.defaults"
  else:
    ui.print "No sdkconfig.defaults found for chip '$chip'."
    ui.abort

create-cmakelists_ dir/string --toit-root/string --sdk-path/string --chip/string --ui/cli.Ui:
  if file.is-file "$dir/CMakeLists.txt":
    ui.print "CMakeLists.txt already exists."
    ui.abort

  cmake-toit-root := to-cmake-path --relative-to=dir toit_root
  cmake-sdk-path := to-cmake-path --relative-to=dir sdk_path
  idf_component_path := "$cmake-toit-root/$TOIT_IDF_COMPONENT_PATH"
  idf_path := "$cmake-toit-root/third_party/esp-idf"

  // This doesn't work if the paths '"' characters.
  // Should be pretty rare.
  file.write-content --path="$dir/CMakeLists.txt" """
    cmake_minimum_required(VERSION 3.5)

    set(IDF_PATH "$idf-path" CACHE FILEPATH "Path to the ESP-IDF directory")
    set(TOIT_SDK_DIR "$cmake-sdk-path" CACHE FILEPATH "Path to the Toit SDK directory")

    list(APPEND EXTRA_COMPONENT_DIRS "$idf-component-path")

    include("\${IDF_PATH}/tools/cmake/project.cmake")
    project(toit)

    include("variant.cmake" OPTIONAL)

    toit_postprocess()
    """

create-makefile_ dir/string --toit-root/string --build-path/string --chip/string --ui/cli.Ui:
  if file.is-file "$dir/Makefile": return

  makefile-toit-root := to-makefile-path --relative-to=dir toit-root
  idf-path := "$makefile-toit-root/third_party/esp-idf"
  if not fs.is-absolute idf-path:
    // Use the Makefile $PWD to make the path absolute.
    idf-path = "\$(PWD)/$idf-path"

  makefile-build-path := to-makefile-path --relative-to=dir build-path

  // This doesn't work if the paths '"' characters.
  // Should be pretty rare.
  file.write-content --path="$dir/Makefile" """
    SHELL := bash
    .SHELLFLAGS += -e

    IDF_PATH := $idf-path
    IDF_PY := \$(IDF_PATH)/tools/idf.py
    TOIT_ROOT := $makefile-toit-root
    BUILD_PATH := $makefile-build-path

    ifeq (\$(OS),Windows_NT)
    \tEXE_SUFFIX=.exe
    else
    \tEXE_SUFFIX=
    endif

    .PHONY: all
    all: esp32

    .PHONY: check-env
    check-env:
    \t\$(MAKE) -C "\$(TOIT_ROOT)" check-env
    \t\$(MAKE) -C "\$(TOIT_ROOT)" check-esp32-env

    .PHONY: esp32
    esp32:
    \tif [ "\$(shell command -v xtensa-esp32-elf-g++)" = "" ]; then source '\$(IDF_PATH)/export.sh'; fi; \\
    \t\$(MAKE) esp32-no-env

    .PHONY: esp32-no-env
    esp32-no-env: check-env
    \tcmake -E env IDF_TARGET=$chip IDF_CCACHE_ENABLE=1 python\$(EXE_SUFFIX) "\$(IDF_PY)" -C . -B"\$(BUILD_PATH)" build
    """

extract-chip-variant_ variant-path/string --ui/cli.Ui -> List:
  slashed := variant-path.replace --all "/" "\\"
  parts := variant-path.split "/"
  // For simplicity we require the variant path to have the last
  // segments be the variant name.
  // This means that we don't allow '.' as path.
  if parts.last == "." or parts.last == "..":
    ui.print "Variant path has invalid last segment. Needs to contain the variant name."
    ui.abort

  variant := parts.last
  chip := variant
  if variant.contains "-":
    chip = variant[..variant.index-of "-"]
  return [chip, variant]

global-print_ str/string -> none:
  print str

class Ui_ implements cli.Ui:
  print str/string: global-print_ str
  abort: exit 1
