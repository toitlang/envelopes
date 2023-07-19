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

The `toit.run` and `toit.pkg` are then in `build/host/sdk/bin`.

In the remainder of this document, we assume that you have added
`build/host/sdk/bin` to your `PATH`. If not, just replace `toit.run`
and `toit.pkg` with the full path to the binaries.

## The envelope tool

The envelope tool is located in the `tools` directory. It can be used
to synthesize a directory with a Makefile that can be used to build a
variant.

Make sure to install its packages first:
```
toit.pkg install --project-root=tools
```

Run it with `toit.run tools/main.toit`.

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
toit.run tools/main.toit synthesize \
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
