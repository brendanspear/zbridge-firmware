# ZBridge Firmware

Firmware overlay implementing the ZBridge protocol on ZuluSCSI hardware: a
direct USB transport between a Mac and vintage Akai samplers over SCSI —
sample/program transfer, fast RAM pull, and live MIDI/CC/SysEx. ZuluSCSI is
one compatible hardware family; ZBridge is this project's protocol and
firmware name.

This repository is a GPLv3 overlay on
[ZuluSCSI-firmware](https://github.com/ZuluSCSI/ZuluSCSI-firmware) — see
[NOTICE.md](NOTICE.md) for the license relationship and [LICENSE](LICENSE)
for the full text. It contains firmware source only; the macOS host
application that talks to this firmware over USB-CDC lives elsewhere and is
not part of this repository (see [NOTICE.md](NOTICE.md)).

## Overview

The current build is a dedicated SCSI-initiator firmware. It creates
samples, keygroups, and programs directly in Akai RAM, pulls them back over a
native USB DATA IN lane, and keeps a persistent live MIDI-via-SCSI session for
playing the result. See [DIRECT_AKAI_TRANSFER.md](DIRECT_AKAI_TRANSFER.md) for
the required S3200XL settings and hardware evidence.

```
┌─────────────────┐     USB CDC      ┌─────────────────┐     SCSI      ┌─────────────┐
│   Host (Mac)    │◄────────────────►│  ZuluSCSI       │◄─────────────►│ Akai S1100  │
│                 │   921600 baud    │  + USB Bridge   │               │             │
└─────────────────┘                  └─────────────────┘               └─────────────┘
```

## Features

- **No SD-card swapping**: Upload complete Akai disk images over USB-C
- **Bidirectional SD access**: Download files from the ZuluSCSI SD card
- **RAM overlay**: 128KB write-back cache for fast updates
- **Event notifications**: Get notified when the Akai reads/writes
- **USB CDC**: No kernel drivers required on macOS
- **Direct Akai RAM transport**: Create and pull samples/programs without a
  disk-image load cycle
- **Live performance route**: notes, CC, realtime, and SysEx via a persistent
  Akai MIDI-via-SCSI session

## Requirements

**Hardware:**
- ZuluSCSI Blaster (RP2350B) or ZuluSCSI RP2040
- USB-C cable
- Akai S1000/S1100/S3000 series sampler
- DB25 SCSI cable

## Repository layout

```
.
├── LICENSE                   # GPL-3.0-or-later, full text
├── NOTICE.md                 # license relationship to upstream ZuluSCSI-firmware
├── SPECIFICATION.md          # ZBridge wire protocol specification
├── DIRECT_AKAI_TRANSFER.md   # required sampler settings + hardware evidence
├── UPSTREAM.lock             # pinned upstream ZuluSCSI-firmware commit
├── include/, src/            # overlay headers/sources added to a ZuluSCSI-firmware checkout
├── pinned-overlay/           # patch set against the pinned upstream commit, plus new files
└── firmware-binaries/        # compiled .uf2 artifacts actually distributed, by build, with provenance
```

## Known-working firmware recovery

`firmware-binaries/v2-working/` holds the RP2040 and Blaster artifacts from
the older SD-card disk-image workflow. `firmware-binaries/build32/`,
`build45/`, `build51/`, and `build52/` are the hardware-proven Direct RAM
lineage; `build52` is the currently-distributed firmware. Flash the
appropriate `.uf2` to roll back from an experimental build.

| Build | SHA-256 |
|---|---|
| `v2-working/ZuluSCSI_RP2040_zulubridge.uf2` | `793fa81b8e2377190c205f46b2ece12edb1369ef49d4c97497ea2ae1a10c77f6` |
| `v2-working/ZuluSCSI_Blaster_zulubridge.uf2` | `8213ac7d702a413724fc5f25d3f232f58280941bea2483b767b814006b37863e` |
| `build45/ZuluSCSI_Blaster_zbridge_direct_candidate.uf2` | `469a22148b102851e8742b941682c2d585af9b21b61a184bcdc6aab8cdae154e` |
| `build51/ZuluSCSI_Blaster_zbridge_direct_candidate.uf2` | `94c031616ae4201079dae8a4c1f2f992273d91c4e5d7ac807aef3b534df6eba6` |
| `build52/ZuluSCSI_Blaster_zbridge_direct_candidate.uf2` (current) | `5ee3a6186465b7568e8bdfbbe3db8071315af305d1929e98d840f47d35fc6556` |

> **Source provenance:** the `include/`/`src/` overlay declares the v2
> file-transfer commands but does not contain their command handlers. The
> upstream checkout and integration tree that produced the working bundled
> firmware were not preserved. Do not treat this overlay as a reproducible
> replacement for the binaries in `firmware-binaries/` until those handlers
> have been reconstructed and hardware-validated. See
> [NOTICE.md](NOTICE.md#known-gap-in-reproducibility).

The integration reference is pinned to an exact upstream revision in
[`UPSTREAM.lock`](UPSTREAM.lock). It is reference-only and is not a claim that
the overlay currently builds a working replacement.

## Reconstructing the firmware integration

### Prerequisites

1. Clone the ZuluSCSI firmware repository at the commit pinned in
   [`UPSTREAM.lock`](UPSTREAM.lock)
2. Set up the PlatformIO build environment
3. Copy the files from this repository into the ZuluSCSI source tree

### Integration steps

1. Copy header files to `lib/ZuluSCSI_platform_*/`:
   ```
   ZuluSCSI_usb_bridge.h
   ZuluSCSI_ram_overlay.h
   ZuluSCSI_platform_cdc.h
   ```

2. Copy source files to `src/`:
   ```
   ZuluSCSI_usb_bridge.cpp
   ZuluSCSI_ram_overlay.cpp
   ZuluSCSI_platform_cdc.cpp
   ZuluSCSI_disk_overlay_hooks.cpp
   ZuluSCSI_main_hooks.cpp
   ```

3. Modify `ZuluSCSI.cpp` main loop:
   ```cpp
   #include "ZuluSCSI_usb_bridge.h"

   // In init:
   usb_bridge_init();

   // In main loop:
   if (scsiDev.phase == BUS_FREE) {
       usb_bridge_poll();
   }
   ```

4. Modify `ZuluSCSI_disk.cpp` for overlay integration:
   ```cpp
   // Before reading from SD:
   if (ram_overlay_read(lba, buffer)) {
       // Served from overlay
   } else {
       // Read from SD
   }

   // After Akai writes:
   disk_overlay_write_hook(lba, buffer, count);
   ```

5. Apply the patches in `pinned-overlay/patches/` in order, and add the files
   in `pinned-overlay/src/`.
6. Restore or reconstruct the missing v2 file-operation handlers (see
   provenance note above), then build a **candidate** firmware artifact. Do
   not overwrite the artifacts in `firmware-binaries/`.
7. Validate the candidate on separate hardware before promoting it.

## Protocol overview

Control, recovery, MIDI, and fallback transfers use a packet protocol over USB
CDC (virtual serial port):

```
┌──────────┬──────────┬──────────┬─────────────────────┬──────────┐
│  SYNC    │  LENGTH  │  OPCODE  │      PAYLOAD        │  CRC16   │
│  2 bytes │  2 bytes │  1 byte  │  0-40960 bytes      │  2 bytes │
└──────────┴──────────┴──────────┴─────────────────────┴──────────┘
```

CRC16-CCITT covers opcode+payload. Legacy block ops carry at most 7 blocks
(7×512 + 6-byte header ≤ 4096). Protocol v5 added capability-gated 40 KiB
frames, v7 added the returned-credit continuous PCM stream, v8 added native
vendor USB DATA OUT, and v9 added native DATA IN plus the concrete Akai live
MIDI route. CDC remains available for control and recovery. See
[SPECIFICATION.md](SPECIFICATION.md) for the wire formats.

## License

GPL-3.0-or-later (matching ZuluSCSI-firmware's license). See
[LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).

## Credits

- ZuluSCSI-firmware / Rabbit Hole Computing: https://github.com/ZuluSCSI/ZuluSCSI-firmware
