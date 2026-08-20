# ZBridge build 51 hardware-proven recovery snapshot

Created: 2026-08-15 (America/New_York)

This snapshot preserves the S-Convert and ZBridge state that passed live
S3200XL OS 2.00 testing over the new protocol-v8 vendor USB transport. The
sampler was discovered at local SCSI ID 6 with ZBridge as initiator/remote ID
7. Exact 1 MiB and unaligned 1,000,000-byte production sample transfers both
completed at approximately 652 KiB/s. Native USB checksum tests passed at
approximately 995 KiB/s, followed by a 32 MiB soak at 1000 KiB/s with matching
host and firmware checksums.

The snapshot was taken from branch `zbridge-recycle-direct` at repository HEAD
`a68e2d092700e29038266eebc75f3770921a284b`. It intentionally includes the
current uncommitted app and transport work rather than relying on HEAD alone.

## Recovery archive

`sconvert-zbridge-build51-hardware-proven.recovery`

SHA-256:

`706a3a78e72d1d460e4186fa1b352c5a88d4bc5d7f162f209f99d40f699ab41a`

The file is a gzip-compressed tar archive with a repository-specific extension.
Inspect it with `tar -tzf` and restore into a clean destination with `tar -xzf`.
It contains 2,081 entries and excludes Swift build output and `.DS_Store`
files. It includes the S-Convert source/tests/project, ZBridge Swift package,
firmware source overlay, reproducible build scripts, and bundled firmware.

## Proven firmware

| Artifact | SHA-256 |
|---|---|
| `ZuluSCSI_Blaster_zbridge_direct_candidate.bin` | `dda0a40fbb931bc4f43c075248dfc249af938d9e103e4fd5719b53d7b0803e51` |
| `ZuluSCSI_Blaster_zbridge_direct_candidate.uf2` | `94c031616ae4201079dae8a4c1f2f992273d91c4e5d7ac807aef3b534df6eba6` |

Build 51 is protocol 8 and reports `51.0.0 (build 51)`. It keeps framed CDC
available for commands, MIDI, recovery, and fallback while native vendor USB
feeds the PIO/DMA SCSI DATA OUT path.
