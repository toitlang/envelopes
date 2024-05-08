// Copyright (C) 2023 Toitware ApS.
// Use of this from code is governed by an MIT-style license that can be
// found in the LICENSE_MIT file.

import host.directory
import host.file
import host.os
import host.pipe
import system show platform PLATFORM-WINDOWS

with-tmp-directory [block]:
  tmpdir := directory.mkdtemp "/tmp/artemis-"
  try:
    block.call tmpdir
  finally:
    directory.rmdir --recursive tmpdir

copy-file --from/string --to/string:
  in-stream := file.Stream.for-read from
  out-stream := file.Stream.for-write to
  try:
    out-stream.out.write-from in-stream.in
    // TODO(florian): we would like to close the writer here, but then
    // we would get an "already closed" below.
  finally:
    in-stream.close
    out-stream.close

tool-path_ tool/string -> string:
  if platform != PLATFORM-WINDOWS: return tool
  // On Windows, we use the <tool>.exe that comes with Git for Windows.

  // TODO(florian): depending on environment variables is brittle.
  // We should use `SearchPath` (to find `git.exe` in the PATH), or
  // 'SHGetSpecialFolderPath' (to find the default 'Program Files' folder).
  program-files-path := os.env.get "ProgramFiles"
  if not program-files-path:
    // This is brittle, as Windows localizes the name of the folder.
    program-files-path = "C:/Program Files"
  result := "$program-files-path/Git/usr/bin/$(tool).exe"
  if not file.is-file result:
    throw "Could not find $result. Please install Git for Windows"
  return result

/**
Copies the $from directory into the $to directory.

If the $to directory does not exist, it is created.
*/
copy-directory --from/string --to/string:
  directory.mkdir --recursive to
  with-tmp-directory: | tmp-dir |
    // We are using `tar` so we keep the permissions.
    tar := tool-path_ "tar"

    tmp-tar := "$tmp-dir/tmp.tar"
    extra-args := []
    if platform == PLATFORM-WINDOWS:
      // Tar can't handle backslashes as separators.
      from = from.replace --all "\\" "/"
      to = to.replace --all "\\" "/"
      tmp-tar = tmp-tar.replace --all "\\" "/"
      extra-args = ["--force-local"]

    // We are using an intermediate file.
    // Using pipes was too slow on Windows.
    // See https://github.com/toitlang/toit/issues/1568.
    pipe.backticks [tar, "c", "-f", tmp-tar, "-C", from, "."] + extra-args
    pipe.backticks [tar, "x", "-f", tmp-tar, "-C", to] + extra-args

/**
Whether the given $path is absolute.

On Windows the term "fully qualified" is often used for absolute paths.
*/
is-absolute path/string -> bool:
  if platform == PLATFORM-WINDOWS:
    if path.starts-with "\\\\" or path.starts-with "//": return true
    return path.size > 2
        and path[1] == ':'
        and (path[2] == '/' or path[2] == '\\')
  else:
    return path.starts-with "/"

make-absolute-slashed path/string -> string:
  slashed := platform == PLATFORM-WINDOWS
      ? path.replace --all "\\" "/"
      : path

  if is-absolute path: return slashed

  // On Windows, we need to handle the case where the path is rooted.
  if platform != PLATFORM-WINDOWS and
     (path.starts-with "/" or path.starts-with "\\" or
      path.size >= 2 and path[1] == ':'):
    throw "rooted paths are not supported: $path"

  cwd := directory.cwd
  slashed-cwd := platform == PLATFORM-WINDOWS
      ? path.replace --all "\\" "/"
      : cwd
  return "$slashed-cwd/$slashed"
