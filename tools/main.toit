// Copyright (C) 2023 Toitware ApS.
// Use of this from code is governed by an MIT-style license that can be
// found in the LICENSE_MIT file.

import cli
import host.file
import host.directory
import host.pipe
import writer show Writer
import .gist as gist
import .git
import .utils

GIT_URL ::= "https://github.com/toitlang/toit.git"
TOIT_IDF_COMPONENT_PATH ::= "toolchains/idf/components"

toit_partition_path_for_ --chip/string -> string:
  return "toolchains/$chip/partitions.csv"
toit_sdk_config_path_for_ --chip/string -> string:
  return "toolchains/$chip/sdkconfig"
toit_sdk_config_defaults_path_for_ --chip/string -> string:
  return "toolchains/$chip/sdkconfig.defaults"
toit_main_path_for_ --chip/string -> string:
  return "toolchains/$chip/main"

main args:
  ui := Ui_
  root_cmd := cli.Command "root"

  variant_list_cmd := cli.Command "list"
      --short_help="List all variants."
      --rest=[
        cli.Option "root"
            --short_help="The root directory to list variants from."
            --default="variants",
      ]
      --run=:: variant_list it --ui=ui
  root_cmd.add variant_list_cmd

  variant_synthesize_cmd := cli.Command "synthesize"
      --long_help="""
        Synthesize the given variants.

        Generates a project that can be compiled for each variant.

        For each variant creates a variant directory in the output root.
        For each variant defines the build directory as 'build-root/variant'.
        """
      --options=[
        cli.Option "output-root"
            --short_name="o"
            --short_help="The output directory to synthesize the variants to.",
        cli.Option "toit-root"
            --short_help="The root directory of the Toit SDK."
            --required,
        cli.Option "build-root"
            --short_help="The output directory for the compilation."
            --required,
        cli.Option "sdk-path"
            --short_help="The path to the Toit SDK. Typically in build/host/sdk."
            --required,
        cli.Option "variants-root"
            --short_help="The root directory of the variants."
            --required,
        cli.Flag "ignore-errors"
            --short_help="Ignore errors when synthesizing variants.",
        cli.Flag "update-patches"
            --short_help="Update the patches in the variants."
            --hidden,
      ]
      --rest=[
          cli.Option "variant"
              --short_help="The variant to synthesize."
              --required
              --multi,
      ]
      --run=:: variant_synthesize it --ui=ui
  root_cmd.add variant_synthesize_cmd

  download_gist_cmd := cli.Command "download-gist"
      --long_help="Download all files of the given gist URL."
      --options=[
        cli.Option "output"
            --short_name="o"
            --short_help="The output directory to download the gist to."
            --required,
      ]
      --rest=[
          cli.Option "gist-url"
              --short_help="The URL of the gist to download."
              --required,
      ]
      --run=:: download_gist it --ui=ui
  root_cmd.add download_gist_cmd

  root_cmd.run args --ui=ui

variant_list parsed/cli.Parsed --ui/cli.Ui:
  root := parsed["root"]
  variants := variant_list --root=root --ui=ui
  variants.do: ui.print it

variant_list --root/string --ui/cli.Ui -> List:
  result := []

  variant_stream := directory.DirectoryStream root
  while variant := variant_stream.next:
    // First level of directory entries are the chips.
    if not file.is_directory "$root/$variant":
      // Skip over files like "README.md".
      continue

    result.add variant
  variant_stream.close
  return result

download_gist parsed/cli.Parsed --ui/cli.Ui:
  output := parsed["output"]
  gist_url := parsed["gist-url"]
  gist.download --output=output --gist_url=gist_url --ui=ui

variant_synthesize parsed/cli.Parsed --ui/cli.Ui:
  toit_root := parsed["toit-root"]
  output_root := parsed["output-root"]
  build_root := parsed["build-root"]
  sdk_path := parsed["sdk-path"]
  variants_root := parsed["variants-root"]
  variants := parsed["variant"]
  ignore_errors := parsed["ignore-errors"]
  update_patches := parsed["update-patches"]

  variants.do: | variant/string |
    exception := catch:
      variant_synthesize
          --variant_path="$variants_root/$variant"
          --toit_root=toit_root
          --output="$output_root/$variant"
          --build_path="$build_root/$variant"
          --sdk_path=sdk_path
          --update_patches=update_patches
          --ui=ui
    if exception:
      ui.print "Failed to synthesize variant '$variant': $exception."
      if not ignore_errors: ui.abort
      catch:
        directory.mkdir --recursive "$output_root/$variant"
        file.write-content --path="$output_root/$variant/failed" "$exception"


variant_synthesize
    --variant_path/string
    --toit_root/string
    --output/string
    --build_path/string
    --sdk_path/string
    --update_patches/bool
    --ui/cli.Ui:
  if file.is_file output:
    ui.print "Output is a file."
    ui.abort

  copy_directory --from="$variant_path/" --to="$output/"

  chip_variant := extract_chip_variant_ variant_path --ui=ui
  chip := chip_variant[0]

  ensure_main_ output --toit_root=toit_root --chip=chip
  ensure_partitions_ output --toit_root=toit_root --chip=chip
  ensure_sdkconfig_ output --toit_root=toit_root --chip=chip --ui=ui
  create_cmakelists_
      output
      --toit_root=toit_root
      --sdk_path=sdk_path
      --chip=chip
      --ui=ui

  create_makefile_
      output
      --toit_root=toit_root
      --build_path=build_path
      --chip=chip
      --ui=ui

  if update_patches:
    if file.is_file "$variant_path/partitions.csv.patch":
      original := "$toit_root/$(toit_partition_path_for_ --chip=chip)"
      patched := "$output/partitions.csv"
      update_patch_
          --from=original
          --to=patched
          --output="$variant_path/partitions.csv.patch"
          --ui=ui

    if file.is_file "$variant_path/sdkconfig.defaults.patch":
      original := "$toit_root/$(toit_sdk_config_defaults_path_for_ --chip=chip)"
      patched := "$output/sdkconfig.defaults"
      update_patch_
          --from=original
          --to=patched
          --output="$variant_path/sdkconfig.defaults.patch"
          --ui=ui

    if file.is_file "$variant_path/main.patch":
      original := "$toit_root/$(toit_main_path_for_ --chip=chip)"
      patched := "$output/main"
      update_patch_
          --from=original
          --to=patched
          --output="$variant_path/main.patch"
          --ui=ui

apply_directory_patch_ --patch_path/string --directory/string --strip/int=1:
  patch := file.read_content patch_path
  args := ["patch", "-d", directory]
  if strip > 0:
    args.add "-p$strip"
  stream := pipe.to args
  writer := Writer stream
  writer.write patch
  writer.close

// Same as $pipe.from but doesn't throw if the exit code is non-zero.
pipe_from arguments/List:
  pipe_ends := pipe.OpenPipe false --child_process_name=arguments[0]
  stdout := pipe_ends.fd
  pipes := pipe.fork true pipe.PIPE_INHERITED stdout pipe.PIPE_INHERITED arguments[0] arguments
  return pipe_ends

apply_file_patch_ --patch_path/string --file_path/string:
  patch := file.read_content patch_path
  args := ["patch", file_path]
  stream := pipe.to args
  writer := Writer stream
  writer.write patch
  writer.close

update_patch_ --from/string --to/string --output/string --ui/cli.Ui:
  ui.print "Updating $output."
  file.delete output
  args := ["diff", "-aur", from, to]
  stream := pipe_from args
  writer := Writer (file.Stream.for_write output)
  while chunk := stream.read:
    writer.write chunk
  writer.close

ensure_main_ dir/string --toit_root/string --chip/string:
  if file.is_directory "$dir/main": return
  main_path := toit_main_path_for_ --chip=chip
  copy_directory --from="$toit_root/$main_path" --to="$dir/main"
  if file.is_file "$dir/main.patch":
    apply_directory_patch_ --patch_path="$dir/main.patch" --directory=dir

ensure_partitions_ dir/string --toit_root/string --chip/string:
  if file.is_file "$dir/partitions.csv": return
  partition_path := toit_partition_path_for_ --chip=chip
  copy_file --from="$toit_root/$partition_path" --to="$dir/partitions.csv"
  if file.is_file "$dir/partitions.csv.patch":
    apply_file_patch_ --patch_path="$dir/partitions.csv.patch" --file_path="$dir/partitions.csv"

ensure_sdkconfig_ dir/string --toit_root/string --chip/string --ui/cli.Ui:
  if file.is_file "$dir/sdkconfig" or file.is_file "$dir/sdkconfig.defaults": return

  if file.is_file "$dir/sdkconfig.patch":
    ui.print "Variants should only patch sdkconfig.defaults, not sdkconfig."
    ui.abort

  sdk_config_defaults_path := toit_sdk_config_defaults_path_for_ --chip=chip

  if file.is_file "$toit_root/$sdk_config_defaults_path":
    copy_file --from="$toit_root/$sdk_config_defaults_path" --to="$dir/sdkconfig.defaults"
    if file.is_file "$dir/sdkconfig.defaults.patch":
      apply_file_patch_ --patch_path="$dir/sdkconfig.defaults.patch" --file_path="$dir/sdkconfig.defaults"
  else:
    ui.print "No sdkconfig.defaults found for chip '$chip'."
    ui.abort

create_cmakelists_ dir/string --toit_root/string --sdk_path/string --chip/string --ui/cli.Ui:
  if file.is_file "$dir/CMakeLists.txt":
    ui.print "CMakeLists.txt already exists."
    ui.abort

  absolute_toit_root := make_absolute_slashed toit_root
  absolute_sdk_path := make_absolute_slashed sdk_path
  idf_component_path := "$absolute_toit_root/$TOIT_IDF_COMPONENT_PATH"
  idf_path := "$absolute_toit_root/third_party/esp-idf"

  // This doesn't work if the paths '"' characters.
  // Should be pretty rare.
  file.write_content --path="$dir/CMakeLists.txt" """
    cmake_minimum_required(VERSION 3.5)

    set(IDF_PATH "$idf_path" CACHE FILEPATH "Path to the ESP-IDF directory")
    set(TOIT_SDK_DIR "$absolute_sdk_path" CACHE FILEPATH "Path to the Toit SDK directory")

    list(APPEND EXTRA_COMPONENT_DIRS "$idf_component_path")

    include("\${IDF_PATH}/tools/cmake/project.cmake")
    project(toit)

    include("variant.cmake" OPTIONAL)

    toit_postprocess()
    """

create_makefile_ dir/string --toit_root/string --build_path/string --chip/string --ui/cli.Ui:
  if file.is_file "$dir/Makefile": return

  absolute_toit_root := make_absolute_slashed toit_root
  idf_path := "$absolute_toit_root/third_party/esp-idf"

  absolute_build_path := make_absolute_slashed build_path

  // This doesn't work if the paths '"' characters.
  // Should be pretty rare.
  file.write_content --path="$dir/Makefile" """
    SHELL := bash
    .SHELLFLAGS += -e

    IDF_PATH := $idf_path
    IDF_PY := \$(IDF_PATH)/tools/idf.py
    TOIT_ROOT := $absolute_toit_root
    BUILD_PATH := $absolute_build_path

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

extract_chip_variant_ variant_path/string --ui/cli.Ui -> List:
  slashed := variant_path.replace --all "/" "\\"
  parts := variant_path.split "/"
  // For simplicity we require the variant path to have the last
  // segments be the variant name.
  // This means that we don't allow '.' as path.
  if parts.last == "." or parts.last == "..":
    ui.print "Variant path has invalid last segment. Needs to contain the variant name."
    ui.abort

  variant := parts.last
  chip := variant
  if variant.contains "-":
    chip = variant[..variant.index_of "-"]
  return [chip, variant]

global_print_ str/string -> none:
  print str

class Ui_ implements cli.Ui:
  print str/string: global_print_ str
  abort: exit 1
