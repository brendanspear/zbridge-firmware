# Direct Akai RAM Transfer

## Goal

Match the useful part of the ReCycle 2 workflow: S-Convert discovers an Akai,
the user clicks Transfer, and the sampler receives new samples plus a playable
program directly into RAM. A disk-image upload remains the reliable first
milestone and fallback, but it is not the final direct-transfer experience.

This document separates hardware-verified behavior from compatibility work.
The old ZBridge v2 firmware is retained as a recovery image; its 4 KiB
stop-and-wait uploader is no longer offered for production transfers.
Protocol-v9 build 52 is hardware-proven on an S3200XL OS 2.00. It retains the
protocol-v8 native vendor USB DATA OUT lane, adds native DATA IN for fast RAM
pulls, and provides a persistent low-latency MIDI-via-SCSI route for playing
the sampler immediately after transfer.

## What ReCycle actually did

ReCycle treated the computer as a SCSI initiator and the Akai sampler as a SCSI
processor target. It did not place an IMG on a disk and ask the user to load it.
Its Transmit operation created slices as individual samples and created a
program that mapped those samples chromatically. It could also copy program
settings from a template already in sampler RAM.

The [ReCycle 2 operation manual](https://cdn.propellerheads.se/download/files/ReCycle2Manual.pdf)
documents that:

- ReCycle scans MIDI and SCSI connections, finds the sampler, and verifies it
  when the application starts.
- Transmit creates samples and a program in the sampler.
- With "Transmit as One Sample" disabled, slices become individual samples and
  the generated MIDI sequence contains one note per slice.
- A template program can supply the starting key, output, MIDI channel, and
  other program settings.

## S3000XL/S3200XL setup

The XL sampler does not need to remain on a receive page. Reception begins
automatically when the remote device initiates the dump. In GLOBAL / EXCL, use
F7 to open the MIDI-via-SCSI page and configure:

- MIDI via SCSI: enabled
- Local SCSI ID: 6 (recommended for the sampler processor target)
- Remote SCSI ID: 7 (recommended for ZBridge/the computer initiator)
- ZBridge emulated disk: ID 5

Every ID on the bus must be unique. Local 6 and remote 6 is invalid and can
cause bus contention. The [Akai S3000XL operator manual's MIDI-via-SCSI page](https://www.manualslib.com/manual/797868/Akai-S3000xl.html?page=243)
explicitly requires different IDs. The S3200XL uses the same XL-family protocol
and controls.

## Verified Akai wire protocol

Akai MIDI-via-SCSI wraps MIDI/System Exclusive messages in four vendor SCSI
commands. The command set recovered from Akai's MESA II plug-in is documented
in the [MESA II SCSI protocol reference](https://github.com/audiocontrol-org/mesa-plug-harness/blob/main/SCSI-PROTOCOL.md):

| CDB | Purpose |
| --- | --- |
| `09 00 MM TT 00 00` | Enable/disable MIDI-via-SCSI and MIDI thru |
| `0C 00 HH MM LL FF` | Send a MIDI/SysEx payload to the sampler |
| `0D 00 00 00 00 FF` | Poll the sampler for pending reply bytes |
| `0E 00 HH MM LL FF` | Read a buffered MIDI/SysEx reply |

A transaction must drain stale pending replies before sending a new request.
Requests that expect a reply must then poll and read until the SysEx terminator
is received. S-Convert uses the XL-safe flag (`FF = 0x00`) on normal send and
poll CDBs;
the tested S3000XL reference implementation rejects the documented `0x80`
variant.
Akai status, program/sample lists, program data, keygroup data,
and sample headers use the SysEx codec already present in S-Convert.

For audio, use the Akai bulk path rather than slow packetized MIDI SDS:

1. Send a sample header to allocate/create the sample.
2. Switch the Akai SCSI session to bulk mode.
3. Send a 16-byte `ASPACK` announcement with sample number, start address, and
   sample count encoded as 7-bit quantities.
4. Transfer uncompressed signed 16-bit PCM in large SCSI data blocks.
5. Return to SCSI-MIDI mode, read the resident header, and update it only when
   the exact restoration bytes differ. The sampler-owned RAM address is never
   overwritten.

The open-source [Lakai implementation](https://sources.debian.org/src/lakai/0.1-2/lakai.c/)
uses up to 65,534 bytes per bulk command and reports about 620 KB/s on period
hardware. Those numbers are useful targets, not a promise for ZBridge.

## ZBridge hardware architecture

Direct Akai transfer requires ZBridge to select the sampler as a SCSI
initiator. The hardware-proven Blaster build therefore boots in dedicated
initiator mode; it cannot simultaneously present HD5 as a disk target.
S-Convert capability-gates this mode and hides disk-image upload while the
Direct RAM firmware is connected.

The host serializes all owners of the processor route. A RAM push or pull
panics and closes any persistent live-MIDI lease, claims the bus for the bulk
operation, verifies the result, and then reopens MIDI-via-SCSI. Any timeout,
USB disconnect, cancellation, or sampler reset releases the PHY, while the
firmware's 15-second idle lease is a final fail-safe.

## Protocol and application milestones

### A. Fast disk-image upload

- Exclusive USB serial ownership (one S-Convert process per ZBridge).
- Atomic file commit and exact byte verification.
- Idempotent quiesce/remount recovery.
- Protocol-v5 40 KiB frame capability is required; old 4 KiB firmware prompts
  for an update instead of silently beginning an hours-long transfer.

### B. Read-only sampler discovery

- New negotiated capability: Akai initiator bridge.
- Enter/exit role handoff without writing sampler memory.
- INQUIRY and status request only.
- Surface model, Akai OS version, local ID, and round-trip time in Sampler
  Setup.

### C. One-sample RAM transfer

- Create one uniquely named sample header.
- Announce through `ASPACK`, then upload uncompressed raw PCM through Akai SCSI
  bulk SEND commands (control `0x80`).
- Read the sample header back and verify name, rate, length, loop points, and
  checksum/PCM where supported.
- Cancel safely without leaving the sampler or bus in transfer mode.

### D. ReCycle-style program creation

- Upload each slice as a sample.
- Create or clone a template program.
- Create one keygroup per slice and map successive notes chromatically.
- Preserve Akai naming limits, program/keygroup structures, envelopes,
  outputs, tuning, and loop metadata.
- Verify the created sample and program lists before reporting success.

### E. Performance/live MIDI

- Use large bulk SCSI blocks for audio; never compress or alter PCM to improve
  transport speed.
- Protocol-v9 build 52 retains about 652 KiB/s Direct RAM DATA OUT and pulls
  20.000 MiB at 596.5 KiB/s end to end (about 639 KiB/s raw DATA IN).
- The Swift host prepares PCM one sample ahead in a bounded detached task. A
  live small-sample profile measured no preparation wait at either completed
  sample boundary.
- Final resident-header restoration is fail-closed: the live SDATA reply is
  compared byte-for-byte with the desired message, including preservation of
  the sampler's RAM address and model extension. The write/ACK is skipped only
  when they already match.
- The app publishes `S-Convert ZBridge` as a CoreMIDI destination. Logic,
  Ableton, Sprocket7, and Forge can send notes, CC, realtime bytes, and complete
  SysEx through it; Sprocket Surface pad edges use the same urgent queue.
- Note-off, zero-velocity note-on, realtime, and panic/controller-reset events
  jump ahead of normal traffic. A disconnected normal queue is bounded, but
  urgent releases are never discarded.
- On S3200XL OS 2.00, live note, CC, and SysEx commands measured 5.36–5.46 ms.
  Other sampler/OS combinations still require their own latency/jitter gate.
- Never allow live MIDI traffic to corrupt or starve an audio transfer.

## Compatibility policy

- Negotiate capabilities; never infer them from a device name alone.
- Keep protocol-v2 firmware available as a recovery image. Require v5 for the
  supported large-frame Direct RAM baseline, v7 for continuous framed PCM,
  v8 for native vendor USB OUT, and v9 for native USB IN and live MIDI.
- Probe Akai model and OS before enabling writes.
- Maintain per-family codecs for S1000/S1100, S2000/S3000XL/S3200XL, and later
  models rather than pretending one header layout fits all units.
- PiSCSI/scsi2pi may implement the same high-level ZBridge operations with a
  different backend. SCSI2SD-style disk-only firmware remains supported by the
  SD-card workflow unless it exposes a safe initiator/raw-command API.
- Do not claim Gotek, PiSCSI, SCSI2SD, ZuluSCSI, or Akai affiliation. They are
  independent products/projects; compatibility names identify third-party
  formats or hardware only.

## Current gate

Protocol-v9 build 52 is reproducible from `Firmware/pinned-overlay/` and is the
firmware bundled by S-Convert. On the connected S3200XL OS 2.00 it passed:

1. exact native-USB checksum tests, including unaligned payloads and a 32 MiB
   soak at about 1000 KiB/s;
2. exact aligned and 1,000,000-byte Direct RAM sample transfers at about
   652 KiB/s;
3. resident header/name verification and exact PCM read-back;
4. a byte-exact 20-sample, 20.000 MiB pull in 34.34 seconds; and
5. note-on/off, CC, complete SysEx, and panic over the persistent live route.

The first optimized host profile completed two 64 KiB samples in 0.481–0.482
seconds each. PCM preparation waited 0.000 seconds, both live headers matched,
and header verification fell from about 88 ms to 54 ms because the redundant
write/ACK was omitted. After clearing and verifying resident RAM, the complete
20-sample test transferred 20.000 MiB in 40.25 seconds: 508.9 KiB/s end to end,
up from the previous 503 KiB/s whole-set result. Raw PCM remained
651.3–652.7 KiB/s; the final firmware SCSI window measured 647.7 KiB/s with no
USB starvation events. The measured gain is therefore a modest fixed-cost
reduction, not a change to the hardware PCM ceiling.

S-Convert can reboot protocol-v5-or-newer firmware into the RP2350 ROM UF2
bootloader, install build 52, and verify the reported version after reconnect.
BOOTSEL remains the recovery path when normal firmware does not enumerate.
Build 45 remains the hardware-proven framed-CDC rollback.

The hardware approval is specific to the S3200XL OS 2.00. Other Akai families
and OS revisions still require their own write/read-back and live-MIDI gates.
