// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this from code is governed by an MIT-style license that can be
// found in the tools/LICENSE file.

import host.directory
import host.file
import host.os
import host.pipe
import writer

with_tmp_directory [block]:
  tmpdir := directory.mkdtemp "/tmp/artemis-"
  try:
    block.call tmpdir
  finally:
    directory.rmdir --recursive tmpdir

copy_file --from/string --to/string:
  in_stream := file.Stream.for_read from
  out_stream := file.Stream.for_write to
  try:
    writer := writer.Writer out_stream
    writer.write_from in_stream
    // TODO(florian): we would like to close the writer here, but then
    // we would get an "already closed" below.
  finally:
    in_stream.close
    out_stream.close

tool_path_ tool/string -> string:
  if platform != PLATFORM_WINDOWS: return tool
  // On Windows, we use the <tool>.exe that comes with Git for Windows.

  // TODO(florian): depending on environment variables is brittle.
  // We should use `SearchPath` (to find `git.exe` in the PATH), or
  // 'SHGetSpecialFolderPath' (to find the default 'Program Files' folder).
  program_files_path := os.env.get "ProgramFiles"
  if not program_files_path:
    // This is brittle, as Windows localizes the name of the folder.
    program_files_path = "C:/Program Files"
  result := "$program_files_path/Git/usr/bin/$(tool).exe"
  if not file.is_file result:
    throw "Could not find $result. Please install Git for Windows"
  return result

/**
Copies the $from directory into the $to directory.

If the $to directory does not exist, it is created.
*/
copy_directory --from/string --to/string:
  directory.mkdir --recursive to
  with_tmp_directory: | tmp_dir |
    // We are using `tar` so we keep the permissions.
    tar := tool_path_ "tar"

    tmp_tar := "$tmp_dir/tmp.tar"
    extra_args := []
    if platform == PLATFORM_WINDOWS:
      // Tar can't handle backslashes as separators.
      from = from.replace --all "\\" "/"
      to = to.replace --all "\\" "/"
      tmp_tar = tmp_tar.replace --all "\\" "/"
      extra_args = ["--force-local"]

    // We are using an intermediate file.
    // Using pipes was too slow on Windows.
    // See https://github.com/toitlang/toit/issues/1568.
    pipe.backticks [tar, "c", "-f", tmp_tar, "-C", from, "."] + extra_args
    pipe.backticks [tar, "x", "-f", tmp_tar, "-C", to] + extra_args

/**
Whether the given $path is absolute.

On Windows the term "fully qualified" is often used for absolute paths.
*/
is_absolute path/string -> bool:
  if platform == PLATFORM_WINDOWS:
    if path.starts_with "\\\\" or path.starts_with "//": return true
    return path.size > 2
        and path[1] == ':'
        and (path[2] == '/' or path[2] == '\\')
  else:
    return path.starts_with "/"

make_absolute_slashed path/string -> string:
  slashed := platform == PLATFORM_WINDOWS
      ? path.replace --all "\\" "/"
      : path

  if is_absolute path: return slashed

  // On Windows, we need to handle the case where the path is rooted.
  if platform != PLATFORM_WINDOWS and
     (path.starts_with "/" or path.starts_with "\\" or
      path.size >= 2 and path[1] == ':'):
    throw "rooted paths are not supported: $path"

  cwd := directory.cwd
  slashed_cwd := platform == PLATFORM_WINDOWS
      ? path.replace --all "\\" "/"
      : cwd
  return "$slashed_cwd/$slashed"
