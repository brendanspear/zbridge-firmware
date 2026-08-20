# ZBridge Direct RAM — hardware-proven pull + live MIDI build 52

This directory is the reproducible source overlay for the ZuluSCSI
Blaster/RP2350B ZBridge protocol-v9 build 52. It is based on upstream
ZuluSCSI firmware release `2026.07.18`, commit
`1e03e1e289788a8ae0f3d6df273d4eadd185ed10`.

Build 52 is the hardware-proven performance firmware bundled with S-Convert.
It preserves build 32's physically proven S3200XL OS 2.00 transfer path: allocate
a native 192-byte S3000-family sample, stream signed 16-bit PCM, restore its
header metadata, and verify the resident sample name. Build 32 also drains
TinyUSB's 256-byte CDC FIFO in batches. On the connected Blaster, that first
fail-closed large-frame path improved from 134.6 kB/s to 397.1 kB/s.

Builds 33–35 added a CRC-checked two-slot queue and RP2350 PIO/DMA DATA OUT,
removed the redundant post-PCM pause, enforced the Akai data-setup interval,
and prevented a reset-low ACK glitch during the SIO-to-PIO handoff. Protocol
v7 keeps one Akai SEND command selected across the complete PCM window. Each
consumed 4 KiB slot returns a credit to the Mac, so USB framing and sampler
handshakes overlap without repeating arbitration, command, status, and message
phases for every chunk. FINISH succeeds only after byte counts, sequences, and
the SCSI command all agree. Every PIO window has a bounded timeout.

Build 45 is the clean, capability-gated continuous-frame fallback path. It
replaces the Mac writer's fixed 1 ms retry sleep with readiness-driven polling,
prefetches a complete 4 KiB credit before feeding PIO/DMA, and gives TinyUSB a
real 4 KiB CDC receive FIFO instead of the precompiled 256-byte queue. PCM
frames retain USB hardware CRC/retry plus byte-count and sequence validation;
control and non-PCM frames retain the ZBridge protocol CRC as well. An earlier
unframed CDC experiment did not pass hardware closure and is neither advertised
nor shipped. On a connected S3200XL OS 2.00, the clean pinned build
45 appended and verified a 512 KiB sample at 509.6 KiB/s firmware-measured PCM
throughput (513.7 KiB/s host-measured at completion) and 1.421 seconds end to
end. Its diagnostic timing reported 324.5 ms of CDC/queue starvation. Deeper
8 KiB credits halved the number of starvation events but did not improve total
throughput, proving the remaining steady-state ceiling is the CDC transport,
not absent Mac-side queueing.

Build 51 adds a standards-compliant vendor-specific USB bulk
interface beside CDC. macOS claims only that interface through IOUSBHost and
submits the complete PCM window as one request; CDC remains independently
scheduled for commands, recovery, and MIDI. Firmware can drain the native bulk
OUT endpoint directly into the PIO/DMA SCSI feeder without the framed CDC ring
or its per-chunk ACKs. Protocol v8 advertises this lane explicitly and retains
build 45's CDC path as a fail-safe fallback. The same endpoint also has a
non-destructive checksum benchmark that does not select SCSI or change Akai
RAM. On the connected S3200XL OS 2.00 it passed exact and unaligned native USB
checksum tests at approximately 995 KiB/s, then appended exact 1 MiB and
1,000,000-byte unaligned samples through the complete production Direct RAM
path at approximately 652 KiB/s. Post-transfer discovery restored the bridge's
normal SCSI role without restarting the sampler. A 32 MiB native USB soak then
completed at 1000 KiB/s on both the host and firmware clocks with a matching
checksum.

Build 52 adds the reverse native USB/SCSI streaming path and a concrete
MIDI-via-SCSI performance route. A byte-exact 20-sample pull copied 20.000 MiB
from the connected S3200XL OS 2.00 in 34.34 seconds (596.5 KiB/s end to end;
approximately 639 KiB/s per PCM window), versus 67.38 seconds and 303.9 KiB/s
on build 51. The same final firmware accepted note-on, note-off, CC, complete
SysEx, and a 16-channel panic at 5.36–5.46 ms host-to-Akai command latency.
MIDI stays on CDC control/SCSI SEND commands; sample DATA IN/OUT stays on the
native vendor endpoint. The paths are serialized, so MIDI is panicked and
released before a bulk transfer and reopened after a successful transfer.

## Hardware mode

This build deliberately boots the Blaster in its native physical initiator
mode. Set the board's **INITIATOR DIP switch ON** and restart the board. On the
Akai, use OS 2.00 and set GLOBAL › MIDI via SCSI to ON, Local 6, Remote 7.

The Blaster cannot be a SCSI initiator and an HD5 disk target at the same time
on this hardware revision. Builds 32 through 52 therefore dedicate the board
to Direct RAM; HD5 is not used and S-Convert hides USB disk-image upload while
this build is connected. Disk images can still be copied through a mounted SD
card.

The direct transport uses selection without ATN first (matching the working
S3200XL path), with an ATN/IDENTIFY fallback. Every command has bounded phase
timeouts and raw signal diagnostics. Protocol v5 also provides software entry
to the RP2350 UF2 bootloader; BOOTSEL remains the recovery path if normal
firmware cannot enumerate. Protocol v7 adds the continuous, returned-credit
PCM stream while retaining that recovery behavior; protocol v8 adds native
vendor USB DATA OUT, and protocol v9 adds native DATA IN and the proven Akai
live-MIDI route while keeping CDC available for commands and recovery.

## Reproducible build

Build with:

```sh
ZBRIDGE_PIO=/path/to/pio ./build-pinned.sh
```

The script clones the exact upstream pin into a new temporary directory,
applies all seven patches, copies the ten source-overlay files, and builds only
`ZuluSCSI_Blaster`. It refuses to reuse a non-empty build directory.

Bundled build-52 checksums:

- BIN: `4821638d38e782e3a7275ab2b6de979bdb5e65a940e8b096c0b9087c0f5cde49`
- UF2: `5ee3a6186465b7568e8bdfbbe3db8071315af305d1929e98d840f47d35fc6556`

These match both the S-Convert resource and the exact hardware-proven recovery
copy in `ZBridge/recovery/2026-08-15-build52-hardware-proven/`.

Build 51 remains available as the native-USB DATA OUT rollback in:

`ZBridge/recovery/2026-08-15-build51-hardware-proven/`

The earlier hardware-proven build 32 recovery snapshot remains in:

`ZBridge/recovery/2026-08-15-build32-hardware-proven/`

Build-32 recovery archive SHA-256:

`bfe18ba9f81a97782e08a201b9b1d8624e287c0cdd17373330c118149cce551e`

Build-45 rollback checksums:

- BIN: `dceeeb639881ba489040740857952a143e596f46d32e750e8c1990a1001ad8f7`
- UF2: `469a22148b102851e8742b941682c2d585af9b21b61a184bcdc6aab8cdae154e`

ZuluSCSI and Akai are independent third-party products/projects. ZBridge and
S-Convert are not affiliated with or endorsed by their owners.
