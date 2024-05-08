// Copyright (C) 2023 Toitware ApS.
// Use of this from code is governed by an MIT-style license that can be
// found in the LICENSE_MIT file.

import fs
import host.directory
import host.file
import host.os
import host.pipe
import system show platform PLATFORM-WINDOWS

with-tmp-directory [block]:
  tmpdir := directory.mkdtemp "/tmp/synth-"
  try:
    block.call tmpdir
  finally:
    directory.rmdir --recursive tmpdir

copy-file --from/string --to/string:
  file.copy --source=from --target=to

/**
Copies the $from directory into the $to directory.

If the $to directory does not exist, it is created.
*/
copy-directory --from/string --to/string:
  directory.mkdir --recursive to
  file.copy --source=from --target=to --recursive

to-cmake-path --relative-to/string path/string -> string:
  return to-slash-relative_ --relative-to=relative-to path

to-makefile-path --relative-to/string path/string -> string:
  return to-slash-relative_ --relative-to=relative-to path

/**
Converts the given $path to a slash-separated path that is
  suitable for cmake and bash-based Makefiles.

If the $path is absolute, it is returned (after converting
  backslashes to slashes).
If the $path is relative, it is converted to a relative path relative to
  the given $relative-to path.
*/
to-slash-relative_ --relative-to/string path/string -> string:
  if fs.is-absolute path:
    return fs.to-slash path

  // On Windows, we need to handle the case where the path is rooted.
  if fs.is-rooted path:
    assert: not fs.is-absolute path
    throw "rooted paths are not supported: $path"


  absolute-path := fs.to-absolute path
  absolute-relative-to := fs.to-absolute relative-to
  relative-path := fs.to-relative absolute-path absolute-relative-to
  return fs.to-slash relative-path

make-absolute-slashed path/string -> string:
  slashed := fs.to-slash path

  if fs.is-absolute path: return slashed

  // On Windows, we need to handle the case where the path is rooted.
  if fs.is-rooted path:
    assert: not fs.is-absolute path
    throw "rooted paths are not supported: $path"

  cwd := directory.cwd
  slashed-cwd := fs.to-slash cwd
  return "$slashed-cwd/$slashed"
