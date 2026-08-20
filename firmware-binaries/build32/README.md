# ZBridge build 32 hardware-proven recovery snapshot

Created: 2026-08-15 (America/New_York)

This snapshot preserves the exact S-Convert and ZBridge Direct RAM state that
successfully transferred a complete conversion to an Akai S3200XL running OS
2.00. The measured transfer reported approximately 152 KB/s end-to-end and
236 KB/s while PCM was actively streaming.

The snapshot was taken from branch `zbridge-recycle-direct` at repository HEAD
`a68e2d092700e29038266eebc75f3770921a284b`. It intentionally includes the
current uncommitted app and transfer work rather than relying on HEAD alone.

## Recovery archive

`sconvert-zbridge-build32-hardware-proven.recovery`

SHA-256:

`bfe18ba9f81a97782e08a201b9b1d8624e287c0cdd17373330c118149cce551e`

The file is a gzip-compressed tar archive with a repository-specific extension.
Inspect it with `tar -tzf` and restore into a clean destination with `tar -xzf`.
It contains 1,693 entries and excludes Swift build output and `.DS_Store` files.

It contains:

- the complete `sconvert/SConvert` application source and bundled resources;
- the S-Convert test target and Xcode project;
- the ZBridge Swift package, sources, and tests;
- the pinned ZuluSCSI firmware overlay and reproducible build scripts;
- the exact build-32 firmware BIN and UF2 installed during the successful
  S3200XL Direct RAM test.

## Proven rollback firmware

| Artifact | SHA-256 |
|---|---|
| `ZuluSCSI_Blaster_zbridge_direct_candidate.bin` | `ec4d25163b3ac2342dab001c56798b4608c09e9f7661eb55eda0675dc41cdeb2` |
| `ZuluSCSI_Blaster_zbridge_direct_candidate.uf2` | `efe8f37adc4bb061a7b8080640ccf1e2fa9883d919cf35e625fd6b42fb0beb92` |

Do not replace these files inside this recovery snapshot. New transport work
must use a new build number and capability bit so S-Convert can distinguish the
experimental path and retain build 32 as the hardware-proven rollback.

