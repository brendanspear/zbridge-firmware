# ZBridge build 52 hardware-proven recovery snapshot

Created: 2026-08-15 (America/New_York)

This directory preserves the exact protocol-v9 UF2 flashed to the connected
ZuluSCSI Blaster and tested against an Akai S3200XL OS 2.00 at sampler/local
SCSI ID 6 and ZBridge/initiator ID 7.

Hardware gates passed:

- note-on: 5.41 ms
- note-off: 5.38 ms
- CC1: 5.36 ms
- complete development SysEx: 5.46 ms
- 16-channel All Sound Off / All Notes Off / Reset Controllers panic
- byte-exact 20-sample pull: 20.000 MiB in 34.34 seconds, 596.5 KiB/s end to
  end and approximately 639 KiB/s per raw PCM window

The firmware reports `52.0.0 (build 52)`, protocol 9. Clean pinned build usage
was 514,400 of 524,288 RAM bytes (98.1%) and 615,108 flash bytes.

| Artifact | SHA-256 |
|---|---|
| `ZuluSCSI_Blaster_zbridge_direct_candidate.uf2` | `5ee3a6186465b7568e8bdfbbe3db8071315af305d1929e98d840f47d35fc6556` |

Build 51 remains the hardware-proven DATA OUT rollback in the adjacent
`2026-08-15-build51-hardware-proven` directory.
