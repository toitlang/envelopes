// Copyright (C) 2023 Toitware ApS.
// Use of this from code is governed by an MIT-style license that can be
// found in the LICENSE_MIT file.

import bytes
import host.pipe
import monitor
import cli show Ui

class Git:
  ui_/Ui

  constructor --ui/Ui:
    ui_ = ui

  /**
  Returns the root of the Git repository that contains the
    current working directory.
  */
  current_repository_root -> string:
    out := run_ [
      "rev-parse",
      "--show-toplevel"
    ]
    return out.trim

  /**
  Inits a new Git repository in the given $repository_root.

  If $origin is given adds the given remote as "origin".
  */
  init repository_root/string --origin/string?=null --quiet/bool?=false:
    args := [
      "init",
      "--initial-branch=main",
      repository_root,
    ]
    if quiet:
      args.add "--quiet"

    run_ args --description="Init of $repository_root"

    if origin:
      args = [
        "-C", repository_root,
        "remote",
        "add",
        "origin",
        origin,
      ]

      run_ args --description="Remote-add of $origin in $repository_root"

  /**
  Sets the configuration $key to $value in the given $repository_root.

  If $global is true, the configuration is set globally.
  */
  config --key/string --value/string --repository_root/string=current_repository_root --global/bool=false:
    args := [
      "-C", repository_root,
      "config",
      key,
      value,
    ]
    if global:
      args.add "--global"

    run_ args --description="Config of $key in $repository_root"

  /**
  Fetches the given $ref from the given $remote in the Git repository
    at the given $repository_root.

  If $depth is given, the repository is shallow-cloned with the given depth.
  If $force is given, the ref is fetched with --force.

  If $checkout is true, the ref is checked out after fetching.
  */
  fetch --ref/string --remote/string="origin"
      --repository_root/string=current_repository_root
      --depth/int?=null
      --force/bool=false
      --checkout/bool=false
      --quiet/bool?=false:
    args := [
      "-C", repository_root,
      "remote",
      "-v",
    ]
    output := run_ args --description="Verbose remote"

    // Debug sleep, to make sure that the init/clone was finished.
    // TODO(florian): remove this again.
    sleep --ms=20

    args = [
      "-C", repository_root,
      "fetch",
      remote,
      // TODO(florian): is the following also useful in the
      // general context?
      "$ref:refs/remotes/$remote/$ref",
    ]
    if depth:
      args.add "--depth"
      args.add depth.stringify
    if force:
      args.add "--force"
    if quiet:
      args.add "--quiet"

    try:
      run_ args --description="Fetch of $ref from $remote"
    finally: | is_exception _ |
      if is_exception:
        // TODO(floitsch): this should be `ui_.error` when that's
        // supported.
        ui_.print "Verbose remote was: $output"

    if checkout:
      args = [
        "-C", repository_root,
        "checkout",
        ref,
      ]
      if quiet:
        args.add "--quiet"

      run_ args --description="Checkout of $ref"

  /**
  Tags the given $commit with the given tag $name.
  */
  tag --commit/string --name/string --repository_root/string=current_repository_root:
    run_ --description="Tag of $name" [
      "-C", repository_root.copy,
      "tag",
      name,
      commit,
    ]

  /**
  Deletes the tag with the given $name.
  */
  tag --delete/bool --name/string --repository_root/string=current_repository_root:
    if not delete: throw "INVALID_ARGUMENT"
    run_ --description="Tag delete" [
      "-C", repository_root,
      "tag",
      "-d",
      name,
    ]

  /**
  Updates the tag with the given $name to point to the given $ref.

  If $force is given, the tag is updated with --force.
  */
  tag --update/bool
      --name/string
      --ref/string
      --repository_root/string=current_repository_root
      --force/bool=false:
    if not update: throw "INVALID_ARGUMENT"
    args := [
      "-C", repository_root,
      "tag",
      name,
      ref,
    ]
    if force:
      args.add "--force"

    run_ args --description="Tag update"

  /**
  Runs the command, and only outputs stdout/stderr if there is an error.
  */
  run_ args/List -> string:
    return run_ args --description="Git command"

  run_ args/List --description -> string:
    output := bytes.Buffer
    stdout := bytes.Buffer
    fork_data := pipe.fork
        --environment=git_env_
        true                // use_path
        pipe.PIPE_INHERITED // stdin
        pipe.PIPE_CREATED   // stdout
        pipe.PIPE_CREATED   // stderr
        "git"
        ["git"] + args

    stdout_pipe := fork_data[1]
    stderr_pipe := fork_data[2]
    pid := fork_data[3]

    semaphore := monitor.Semaphore
    stdout_task := task::
      catch --trace:
        while chunk := stdout_pipe.read:
          output.write chunk
          stdout.write chunk
      semaphore.up

    stderr_task := task::
      catch --trace:
        while chunk := stderr_pipe.read:
          output.write chunk
      semaphore.up

    2.repeat: semaphore.down
    exit_value := pipe.wait_for pid

    if (pipe.exit_code exit_value) != 0:
      // TODO(floitsch): these should be `ui_.error` when that's
      // supported.
      ui_.print "$description failed"
      ui_.print "Git arguments: $args"
      ui_.print output.bytes.to_string_non_throwing
      ui_.abort

    return stdout.bytes.to_string_non_throwing

  git_env_ -> Map:
    return {
      "GIT_TERMINAL_PROMPT": "0",  // Disable stdin.
    }
