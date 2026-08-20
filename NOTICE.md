# Notice

This repository is a source-available overlay on top of **ZuluSCSI-firmware**,
copyright its respective contributors, licensed under the **GNU General
Public License v3.0 or later**:

- Upstream project: https://github.com/ZuluSCSI/ZuluSCSI-firmware
- Upstream author/maintainer: Rabbit Hole Computing
- Pinned upstream commit: see [`UPSTREAM.lock`](UPSTREAM.lock)

Everything in this repository — the `include/` and `src/` overlay files, the
`pinned-overlay/` patch set and additions, and the compiled artifacts under
`firmware-binaries/` — is a modification of or addition to that GPLv3
codebase, and is licensed under the same terms. See [`LICENSE`](LICENSE) for
the full text.

## What this repository is not

This repository does **not** include the macOS host application (SConvert)
or its Swift ZBridge framework. That code communicates with this firmware as
a separate program over a USB-CDC serial protocol (see
[`SPECIFICATION.md`](SPECIFICATION.md)) — it is not linked with, and does not
incorporate, any code from this repository or from ZuluSCSI-firmware. It is
not covered by, and not required to comply with, this repository's GPLv3
license.

## Known gap in reproducibility

The `pinned-overlay/patches/` in this repository are diffs against the
upstream commit pinned in `UPSTREAM.lock`. As of this writing, the exact
integration tree that produced the currently-shipped `build52`
(`firmware-binaries/build52/`) binary was not fully preserved — some command
handlers referenced by the overlay are not reconstructable from what is
committed here. This is disclosed rather than hidden: treat the `.uf2`
binaries as the authoritative record of what is actually distributed, and the
source here as the best-available (but currently incomplete) corresponding
source, pending reconstruction. See each `firmware-binaries/build*/README.md`
for the specific provenance of that build.

## Status

This repository is currently **private**, shared for review with Rabbit Hole
Computing ahead of making it public.
