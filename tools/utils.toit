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

/**
Whether the given $path is absolute.

On Windows the term "fully qualified" is often used for absolute paths.
*/
is-absolute path/string -> bool:
  return fs.is-absolute path

make-absolute-slashed path/string -> string:
  slashed := fs.to-slash path

  if is-absolute path: return slashed

  // On Windows, we need to handle the case where the path is rooted.
  if fs.is-rooted path:
    assert: not fs.is-absolute path
    throw "rooted paths are not supported: $path"

  cwd := directory.cwd
  slashed-cwd := fs.to-slash cwd
  return "$slashed-cwd/$slashed"
