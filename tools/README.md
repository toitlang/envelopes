# Envelope tool
The envelope tool makes it easy to generate firmware envelopes with
different configurations (like `sdkconfig`).

We call these configurations "variants".

## Toit Host SDK

The envelopes and the envelope tool need the Toit SDK to be available.

The easiest way to get it is by running
```
make download-toit TOIT_VERSION=<some version>
make build-host
```

This will checkout the Toit repository into a `toit` directory and
build the host SDK into `build/host/sdk`.

The `toit` executable is then in `build/host/sdk/bin`.

In the remainder of this document, we assume that you have added
`build/host/sdk/bin` to your `PATH`. If not, just replace `toit`
with the full path to the binary.

## The envelope tool

The envelope tool is located in the `tools` directory. It can be used
to synthesize a directory with a Makefile that can be used to build a
variant.

Make sure to install its packages first:
```
toit pkg install --project-root=tools
```

Run it with `toit tools/main.toit`.

### Synthesizing a variant

To synthesize a variant, run the tool with the `synthesize` command. This
creates a directory with the necessary `CMakelists.txt`, a C++ entrypoint
and `Makefile` to build it.

It requires a few arguments:
- `--toit-root`: The root directory of the Toit repository. If you
  have used `make download-toit`, this is just `toit`.
- `--build-root`: The root directory of the build. Typically, this is
  just `build`. The generated `Makefile` will generate the firmware
  into `build/<variant>`.
- `--output-root`: The root directory of the generated files. Typically,
  this is just `synthesized`. The generated `Makefile` will generate
  the firmware into `synthesized/<variant>`.
- `--sdk-path`: The path to the Toit SDK. If you have used
  `make download-toit` and `make build-host` this is `build/host/sdk`.
- `--variants-root`: The root directory of the variants. Almost always
  this is just `variants`.

For example:
```
toit run tools/main.toit -- synthesize \
			--toit-root=toit \
			--build-root=build \
			--output-root=synthesized \
			--sdk-path=build/host/sdk \
			--variants-root=variants \
			esp32 esp32-eth-clk-out17
```

You can also use `make synthesize-all` to synthesize all variants.

Note that the script won't overwrite existing files. You need to
remove synthesized directories first, if you want to regenerate them.

### Building a variant

Call `make` in the synthesized directory to build the variant.

### Updating the sdkconfig patches

After checking out the desired Toit revision and updating its ESP-IDF submodule,
run:

```
make update-patches
```

This requires the host SDK, the envelope tool's packages, and the ESP-IDF tools
for the affected chips to be installed. The command activates the ESP-IDF
environment from the Toit checkout automatically.

`variants/sdkconfig.base` records the Toit commit that the patches apply to.
The updater reads that commit's defaults with Git, reconstructs each variant,
and transfers its configuration differences onto the current checkout's defaults.
Upstream changes to unrelated settings are preserved. It then runs
`idf.py save-defconfig` for each patched variant, checks that explicit variant
settings still take effect, and verifies that the generated defaults reproduce
the effective configuration.

The replacement patch contains only the migrated original variant edits.
ESP-IDF's normalized defaults are used for validation, not as the patch target:
omitting a redundant SDK assignment during normalization must not add an unrelated
deletion to the variant patch. SDK comments and assignments outside the variant's
changes are preserved.

All configurations are generated before any patches are replaced. On success,
the updater also advances `variants/sdkconfig.base` to the current Toit commit;
commit that file together with the updated patches. Repeating the command on
the same checkout is supported. It uses fresh temporary projects under `build/`
and does not change the Toit checkout or existing `synthesized/` projects.

If both upstream and a variant changed the same setting differently, the updater
stops and reports the setting and its three values. Configuration failures,
including explicit variant settings that no longer take effect, also stop the
update. Working files and logs are retained in the directory printed on failure.
Review and resolve these changes before rerunning the command.

The recorded commit must be available in the local Toit Git history. For older
patch sets without a baseline file, or to correct a recorded base, specify the
Toit commit or tag against which **all** patches were generated:

```
make update-patches PATCH_BASE=<old-toit-commit-or-tag>
```

The old positional `tools/update-patches.sh BEFORE AFTER` interface is replaced
by this command; the target is always the current Toit checkout.
