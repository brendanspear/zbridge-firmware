# ZBridge known-working v2 recovery snapshot

Created: 2026-08-05 (America/New_York)

This snapshot preserves the ZBridge firmware artifacts that successfully connected
to S-Convert and transferred an Akai disk image, together with the current Swift
host implementation, tests, firmware overlay, protocol documentation, firmware
catalog, and S-Convert integration.

## Recovery archive

`zbridge-working-v2-source-and-firmware.recovery`

SHA-256:

`e781398498f52cfee88bd4100e9593d0185c4f01717faf25d52da928e55f2027`

The file is a gzip-compressed tar archive with a repository-specific extension so
that it is not discarded by the repository's general archive ignore rule. It can
be inspected with `tar -tzf` and extracted with `tar -xzf`.

The archive contains 35 entries. It intentionally excludes Swift build output,
SwiftPM user data, and `.DS_Store` files.

## Proven working firmware artifacts

| Artifact | SHA-256 |
|---|---|
| `ZuluSCSI_Blaster_zulubridge.bin` | `6c9046b047208b596fe38355b97be3f4a03bf378fdc52f0b24d9472bb3f863e9` |
| `ZuluSCSI_Blaster_zulubridge.uf2` | `8213ac7d702a413724fc5f25d3f232f58280941bea2483b767b814006b37863e` |
| `ZuluSCSI_RP2040_zulubridge.bin` | `889a264491fd3b419e60adfad665ea98a7b8b7cab8a15a22f3f986687c82946c` |
| `ZuluSCSI_RP2040_zulubridge.uf2` | `793fa81b8e2377190c205f46b2ece12edb1369ef49d4c97497ea2ae1a10c77f6` |

The Blaster artifacts are the firmware actually exercised on hardware. Preserve
these exact files as the rollback image. Do not overwrite them with an experimental
build.

## Source-provenance warning

The repository history contains the v2 Swift file-transfer implementation in
commit `34a9a5e5`, and first tracks the current `ZBridge/Firmware` overlay in commit
`ab7dda91`. The checked-in firmware overlay declares file-transfer commands
`0x20` through `0x25` and device-control commands `0x30` through `0x31`, but its
command dispatcher does not implement them. It therefore cannot be the complete
source tree that produced the known-working v2 firmware artifacts above.

The original upstream ZuluSCSI checkout, exact upstream revision, integration
edits, and final build tree used to produce those artifacts were not found in this
repository or its history. Until that source is recovered or reconstructed and
validated, treat the bundled binary and UF2 as the authoritative recovery copy and
the firmware overlay as incomplete reference material only.

## Compatibility and optimization boundary

Any future transport optimization must:

1. Negotiate an explicit capability before using a new command or framing mode.
2. Fall back automatically to the known-working v2 stop-and-wait file protocol.
3. Leave every byte of the generated Akai image unchanged.
4. Keep the existing staged `.part` write and atomic commit behavior.
5. Verify the committed file size and checksum before sampler remount.
6. Never replace the recovery firmware artifacts until hardware tests pass on a
   separate candidate build.

This permits changes to buffering, packet scheduling, acknowledgement strategy,
and USB/SD write batching. It does not permit compression, audio re-encoding,
filesystem-layout changes, or altered Akai image construction.
