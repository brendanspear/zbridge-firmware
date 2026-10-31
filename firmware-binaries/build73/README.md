# Build 73 — SD disk / Direct RAM, protocol 9

Built from patches 0001–0010 plus `pinned-overlay/src` on the pinned upstream.
Board: ZuluSCSI Blaster. GET_INFO firmware word: `0x49000049`.

| File | SHA-256 |
|---|---|
| ZuluSCSI_Blaster_zbridge_direct_candidate.bin | 98e5011dff2886e7229bfaeb5adfa8367069cc13f7452f98ffd897786c11b092 |
| ZuluSCSI_Blaster_zbridge_direct_candidate.uf2 | 244800ddf52ecad7a57bb0f2bfce63706ce8978b8c85d8f6086a344a590fb463 |

The UF2 payload is byte-for-byte identical to the BIN.

## Changes since build 54

- **55–65:** S1000 OS 4.40 support (discovery, session and PIO lifecycle fixes).
- **68:** opcode 0x35 switches a SCSI ID to another equal-capacity root `HDn`
  image while the sampler stays on. Capability bit 18.
- **69:** the mount runs outside the CDC packet path. Build 68 overflowed the
  3 KB core-0 stack inside `ExFatFile::open`.
- **70:** disk mode advertises large frames (bit 10), so the host can upload
  images.
- **72:** after a live mount, the replaced image is renamed `OLD_<name>`.
  A reboot then keeps the new image.
- **73:** opcode 0x26 streams a whole file over the vendor bulk endpoint after
  FILE_OPEN_WRITE (capability bit 20), and COMMIT drains the stream.
  - Upload speed: 986–990 KiB/s, against 313 KiB/s for framed CDC.
  - `zbridge_poll` now reads the clock after its pumps. Before, it read it
    first, so the idle check wrapped and the 3 s timeout fired mid-stream.
  - The boot scan ignores `.part` files.

## Hardware, 2026-10-31

| Sampler | Mode | Firmware | Result |
|---|---|---|---|
| Akai S950 | SD disk | build 73 | Streamed upload, live mount and image retirement passed. The sampler stayed powered on. |
| Akai S1000 OS 4.40 | Direct RAM | build 73 | Discovery, read-only RAM pull, and a live MIDI-via-SCSI session with a program-list SysEx reply passed. |
| Akai S1000 OS 4.40 | Direct RAM | build 70 | Send and front-panel playback passed. |
| Akai S3200XL OS 2.00 | Direct RAM | build 70 | Discovery passed. Not yet run on build 73. |

## Flashing without a power cycle

A bridge keeps running on SCSI termination power while its sampler is on,
so unplugging USB does not restart it. To flash:

1. Upload `ZuluSCSI_Blaster_zbridgeNN.bin` to the SD card over ZBridge.
2. Send reboot-to-BOOTSEL.
3. Run `picotool reboot -a --ser <serial>`.

The normal boot then applies the SD update and deletes the file.

The version banner timestamp is stale. Identify the build by its GET_INFO
firmware word.
