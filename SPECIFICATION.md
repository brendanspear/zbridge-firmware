# ZBridge Protocol Specification
## Version 9.0

> **v9.0 changes (summary):**
> - Adds capability-gated continuous Akai DATA IN (`0x5A`–`0x5C`) over the
>   vendor USB endpoint.
> - Gives the existing MIDI batch/flush commands a concrete Akai
>   MIDI-via-SCSI implementation while a direct initiator session is active.
> - Bulk sample streams and live MIDI are mutually exclusive owners of the
>   SCSI processor route; hosts must panic/release MIDI before bulk transfer.

> **v8.0 changes (summary):**
> - Adds the native vendor USB DATA OUT lane and checksum benchmark.

> **v7.0 changes (summary):**
> - Adds the returned-credit continuous framed PCM stream.

> **v5.0 changes (summary):**
> - Adds capability bit 10 (`largeTransferFrames`).
> - Negotiates a 40 KiB maximum frame for file writes and direct-SCSI commands,
>   reducing image-upload acknowledgements by 10×.
> - Hosts must not infer large-frame support from a product name or version.
> - S-Convert requires this capability for image and direct-RAM bulk transfer;
>   old 4 KiB firmware remains connectable for recovery/update only.

> **v4.0 changes (summary):**
> - Adds serialized Akai direct-session commands (`0x51`–`0x53`) and software
>   bootloader command `0x32`.

> **v3.0 changes (summary):**
> - The product/protocol name is ZBridge. ZuluSCSI remains one compatible
>   third-party hardware family.
> - Adds capability-negotiated timestamped MIDI batches (`0x40`), MIDI flush
>   (`0x41`), and MIDI input notifications (`0xE7`).
> - MIDI support is optional. Firmware must not advertise it without a real
>   board-level MIDI route; hosts retain CoreMIDI fallback.
> - Reserves a capability-gated, read-only Akai discovery request (`0x50`) and
>   identity response (`0x90`). Firmware must not advertise it until its board
>   integration can restore disk-target mode on every exit path.

> **v2.0 changes (summary):**
> - CRC16 is computed over **OPCODE + PAYLOAD** only (v1 documented LENGTH+OPCODE+PAYLOAD).
> - Max blocks per READ_BLOCKS/WRITE_BLOCKS corrected to **7** (v1 said 8; 8×512 + 6-byte
>   header = 4102 > 4096, which never fit in the max payload — v1 math error).
> - RSP_DEVICE_INFO redefined as a fixed **64-byte** struct with a hardware serial and a
>   user label so multiple devices are distinguishable.
> - New **file-level transfer ops** (0x20–0x25): the firmware owns the FAT filesystem and
>   the host transfers whole files. This replaces raw-LBA sample writing as the primary
>   workflow.
> - New device-control ops: **CMD_EJECT_CYCLE (0x30)** and **CMD_QUIESCE (0x31)**.
> - The LBA + RAM-overlay command set is retained but demoted to **legacy/optional**
>   (section 8).

---

## 1. Overview

### 1.1 Purpose

The ZuluSCSI USB Bridge enables direct communication between a Mac application (SConvert) and vintage Akai samplers via a ZuluSCSI device. This eliminates the need for SD card swapping by allowing sample/image transfers over USB while the sampler remains connected via SCSI.

### 1.2 System Requirements

**Hardware:**
- ZuluSCSI Blaster (RP2350B) or ZuluSCSI RP2040
- USB-C cable
- Mac with USB-C or USB-A port
- Akai S1000/S1100/S3000 series sampler
- DB25 SCSI cable

**Software:**
- macOS 13.0 or later
- Compatible firmware with ZBridge protocol v5 fast-transfer support
- SConvert application with ZBridge framework

### 1.3 Architecture Overview

```
┌─────────────────┐     USB CDC      ┌─────────────────┐     SCSI      ┌─────────────┐
│   Mac/SConvert  │◄────────────────►│  ZuluSCSI       │◄─────────────►│ Akai S1100  │
│                 │                  │  + USB Bridge   │               │             │
└─────────────────┘                  └─────────────────┘               └─────────────┘
```

Primary bulk workflow: the host uploads/downloads **files** on the SD card
(CMD_LIST_FILES / CMD_FILE_*), optionally pausing firmware SCSI activity with
CMD_QUIESCE during the transfer, then pulses CMD_EJECT_CYCLE so the sampler
re-mounts the updated image.

---

## 2. Transport Layer

### 2.1 Physical Layer

| Parameter | Value |
|-----------|-------|
| Interface | USB CDC ACM control + capability-gated vendor bulk IN/OUT |
| Speed | USB 1.1 Full Speed (12 Mbps) |
| Baud Rate | Ignored — CDC-ACM has no physical UART. Hosts may set a nominal 921600. |
| Data Bits | 8 |
| Parity | None |
| Stop Bits | 1 |
| Flow Control | None (protocol handles flow) |

### 2.2 Device Identification

The ZuluSCSI will appear as a USB CDC device with:
- Vendor ID: 0x1209 (pid.codes)
- Product ID: 0x2053 (ZuluSCSI Bridge - to be registered)
- Device Name: "ZuluSCSI Bridge"
- Serial Port Pattern: `/dev/cu.usbmodem*` on macOS

Host discovery policy (v2): match strictly on VID/PID (or an IOKit name
containing "ZuluSCSI"). Matching *any* usbmodem port is opt-in only, and every
candidate must be confirmed with CMD_GET_INFO before use. The serial and label
fields of RSP_DEVICE_INFO distinguish multiple connected devices.

### 2.3 Connection States

```
DISCONNECTED ──► CONNECTING ──► CONNECTED ──► ACTIVE
      ▲              │              │            │
      └──────────────┴──────────────┴────────────┘
                    (on error or disconnect)
```

### 2.4 Link Discipline

The link is **stop-and-wait**: the host keeps at most ONE command outstanding
and waits for its response (or a timeout) before sending the next. The device
may interleave asynchronous notification frames (opcodes ≥ 0xE0) at any time;
they are not responses and must not complete a pending command.

Retransmission: on a CRC failure in either direction (host receives a corrupt
frame, or the device answers RSP_ERROR/ERR_CRC_MISMATCH), the host retransmits
the command **once**. File chunk commands carry explicit offsets and are
idempotent, so a chunk whose ack was lost may also be retransmitted once after
a timeout.

Transport implementations may optimize local CRC calculation, memory mapping,
buffer allocation, and UI progress scheduling without negotiation, provided
they produce the identical framed byte stream. Windowed writes, pipelining,
cumulative acknowledgements, sparse transfer, compression, or any other wire
change requires a new advertised capability. Protocol v5 keeps stop-and-wait
but negotiates a 40 KiB frame, amortizing each acknowledgement across 10× more
data than the legacy 4 KiB envelope.

---

## 3. Packet Format

### 3.1 Packet Structure

All communication uses length-prefixed packets with CRC verification:

```
┌──────────┬──────────┬──────────┬─────────────────────┬──────────┐
│  SYNC    │  LENGTH  │  OPCODE  │      PAYLOAD        │  CRC16   │
│  2 bytes │  2 bytes │  1 byte  │   0-40960 bytes     │  2 bytes │
└──────────┴──────────┴──────────┴─────────────────────┴──────────┘
```

### 3.2 Field Definitions

| Field | Size | Description |
|-------|------|-------------|
| SYNC | 2 bytes | Fixed value `0xAA 0x55` (little-endian: `0x55AA`) |
| LENGTH | 2 bytes | Unsigned 16-bit LE, includes OPCODE + PAYLOAD length (1–40961) |
| OPCODE | 1 byte | Command or response identifier |
| PAYLOAD | 0-40960 bytes | Command-specific data; large data requires capability bit 10 |
| CRC16 | 2 bytes | CRC-16-CCITT over **OPCODE + PAYLOAD**, little-endian |

### 3.3 CRC Calculation

CRC-16-CCITT with polynomial 0x1021, initial value 0xFFFF, computed over the
OPCODE byte followed by the PAYLOAD bytes:

```c
uint16_t crc16_ccitt(const uint8_t* data, size_t length) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < length; i++) {
        crc ^= (uint16_t)data[i] << 8;
        for (int j = 0; j < 8; j++) {
            if (crc & 0x8000) {
                crc = (crc << 1) ^ 0x1021;
            } else {
                crc <<= 1;
            }
        }
    }
    return crc;
}
```

Known vector: `crc16_ccitt("123456789", 9) == 0x29B1`.

### 3.4 Byte Order

All multi-byte integers are transmitted in **little-endian** format.

### 3.5 Maximum Packet Size

| Component | Max Size |
|-----------|----------|
| Payload | 40960 bytes (v5 capability); 4096 bytes legacy |
| Total Packet | 40967 bytes (2 + 2 + 1 + 40960 + 2) |
| Blocks per legacy READ/WRITE | **7** (7 × 512 + 6-byte header = 3590 ≤ 4096) |
| FILE_WRITE_CHUNK data | 40956 bytes (v5) / 4088 bytes (legacy) |
| FILE_READ_CHUNK data | 4089 bytes (ACK status + u32 offset + u16 length share the 4096-byte payload) |

> v1 stated "8 blocks per transfer (8 × 512 = 4096)". That was wrong: the
> block ops carry a 6-byte lba/count header inside the same 4096-byte payload,
> so 8 blocks (4102 bytes) never fit. The limit is 7.

### 3.6 Resynchronization

Receivers must treat the byte stream as unreliable: scan for `AA 55`, validate
the LENGTH field (1–40961), and verify the CRC. On garbage, a bogus header, or
a CRC failure, drop bytes up to (or past) the sync word and rescan from the
next byte — reception must always recover at the next genuine `AA 55`.

---

## 4. Command Reference

### 4.1 Command Opcodes (Host → Device)

| Opcode | Name | Status | Description |
|--------|------|--------|-------------|
| 0x01 | CMD_PING | active | Connection test |
| 0x02 | CMD_GET_INFO | active | Get device information (64-byte response) |
| 0x03 | CMD_READ_BLOCKS | legacy | Read blocks from disk image (max 7) |
| 0x04 | CMD_WRITE_BLOCKS | legacy | Write blocks to RAM overlay (max 7) |
| 0x05 | CMD_SYNC_TO_SD | legacy | Flush overlay to SD card |
| 0x06 | CMD_GET_DIRTY_BLOCKS | legacy | Get list of modified blocks |
| 0x07 | CMD_CLEAR_OVERLAY | legacy | Discard overlay changes |
| 0x08 | CMD_GET_SCSI_STATUS | active | Get current SCSI bus state |
| 0x09 | CMD_SUBSCRIBE_EVENTS | active | Enable async notifications |
| 0x0A | CMD_SET_ACTIVE_IMAGE | legacy | Select disk image |
| 0x0B | CMD_GET_OVERLAY_STATS | legacy | Get overlay statistics |
| 0x0C | CMD_READ_OVERLAY_ONLY | legacy | Read only from overlay |
| 0x0D | CMD_INVALIDATE_BLOCK | legacy | Remove block from overlay |
| 0x20 | CMD_LIST_FILES | **v2** | List SD card directory (paginated) |
| 0x21 | CMD_FILE_OPEN_WRITE | **v2** | Open a file for writing (staged as `name.part`) |
| 0x22 | CMD_FILE_WRITE_CHUNK | **v2** | Write a data chunk at an explicit offset |
| 0x23 | CMD_FILE_CLOSE_COMMIT | **v2** | Close and atomically rename over the final name |
| 0x24 | CMD_FILE_READ_OPEN | **v2** | Open a file for reading (returns size) |
| 0x25 | CMD_FILE_READ_CHUNK | **v2** | Read a data chunk at an explicit offset |
| 0x30 | CMD_EJECT_CYCLE | **v2** | Fixed-disk eject/reinsert pulse |
| 0x31 | CMD_QUIESCE | **v2** | Pause/resume firmware SCSI-side activity |
| 0x32 | CMD_REBOOT_BOOTLOADER | **v4 optional** | Enter the RP2 ROM UF2 bootloader |
| 0x40 | CMD_MIDI_SEND_BATCH | **v3 optional** | Queue timestamped MIDI events on an advertised route |
| 0x41 | CMD_MIDI_FLUSH | **v3 optional** | Flush one MIDI adapter port |
| 0x50 | CMD_AKAI_DISCOVER | **v3 optional** | Read-only TEST UNIT READY / INQUIRY through a safe role handoff |
| 0x51 | CMD_AKAI_SESSION_BEGIN | **v4 optional** | Begin a bounded Akai processor initiator session |
| 0x52 | CMD_AKAI_SCSI_EXECUTE | **v4 optional** | Execute one validated SCSI CDB in that session |
| 0x53 | CMD_AKAI_SESSION_END | **v4 optional** | Release the initiator session |
| 0x54–0x57 | CMD_AKAI_BULK_* | **v7 optional** | Continuous returned-credit Akai DATA OUT |
| 0x58–0x59 | CMD_USB_BULK_BENCH_* | **v8 optional** | Non-destructive vendor endpoint checksum test |
| 0x5A–0x5C | CMD_AKAI_BULK_READ_* | **v9 optional** | Continuous Akai DATA IN over native USB |

### 4.2 Response Opcodes (Device → Host)

| Opcode | Name | Description |
|--------|------|-------------|
| 0x81 | RSP_PONG | Response to PING, SUBSCRIBE_EVENTS, CLEAR_OVERLAY |
| 0x82 | RSP_DEVICE_INFO | Device information (64 bytes) |
| 0x83 | RSP_BLOCK_DATA | Block read response |
| 0x84 | RSP_ACK | Generic acknowledgment (see 4.4) |
| 0x85 | RSP_SYNC_COMPLETE | SD sync result |
| 0x86 | RSP_DIRTY_BLOCK_LIST | Modified block list |
| 0x87 | RSP_SCSI_STATUS | SCSI bus state |
| 0x88 | RSP_OVERLAY_STATS | Overlay statistics |
| 0x8F | RSP_ERROR | Error response |
| 0x90 | RSP_AKAI_DEVICE | Fixed-width Akai INQUIRY identity |

### 4.3 Notification Opcodes (Device → Host, Async)

All opcodes ≥ 0xE0 are asynchronous notifications.

| Opcode | Name | Description |
|--------|------|-------------|
| 0xE1 | NOTIFY_SCSI_COMMAND | SCSI command detected |
| 0xE2 | NOTIFY_BLOCKS_WRITTEN | Akai wrote blocks |
| 0xE3 | NOTIFY_OVERLAY_FULL | RAM overlay at capacity |
| 0xE4 | NOTIFY_SD_REMOVED | SD card ejected |
| 0xE5 | NOTIFY_SD_INSERTED | SD card inserted |
| 0xE6 | NOTIFY_SCSI_BUS_RESET | SCSI bus was reset |
| 0xE7 | NOTIFY_MIDI_INPUT | Timestamped MIDI input batch |

### 4.4 RSP_ACK (0x84) — v2 acknowledgment

Every **v2** command (0x20–0x25, 0x30, 0x31) is acknowledged with RSP_ACK:

```
┌─────────┬─────────────────────────────────────┐
│ status  │ op-specific payload (optional)      │
│ u8      │ defined per command in section 6    │
└─────────┴─────────────────────────────────────┘
```

`status = 0x00` means OK. A non-zero status is an error code from section 7.2
(the device may equivalently answer with a full RSP_ERROR frame — hosts must
accept both).

**Note:** 0x84 is the same opcode as v1's RSP_WRITE_ACK. Legacy
CMD_WRITE_BLOCKS keeps its v1 response payload on this opcode
(`start_lba u32 + block_count u16 + overlay_used u16`, **no** status byte).
The stop-and-wait discipline makes the two layouts unambiguous: the pending
command determines the parse.

---

## 5. Core Command Details

### 5.1 CMD_PING (0x01)

Tests connection and measures round-trip latency.

**Request:** (none)
**Response:** RSP_PONG (0x81), no payload.

### 5.2 CMD_GET_INFO (0x02)

Retrieves device identity and state.

**Request:** (none)

**Response: RSP_DEVICE_INFO (0x82) — exactly 64 bytes**

| Offset | Type | Field | Description |
|--------|------|-------|-------------|
| 0  | u32      | fw_version   | Firmware version; LE bytes = [major, minor, patch, build] |
| 4  | u16      | protocol_ver | Protocol version (current = **9**) |
| 6  | u32      | capabilities | Capability bits (see below) |
| 10 | u8       | scsi_id      | SCSI device ID (0-7) of the active image |
| 11 | u8       | num_images   | Number of disk images on SD |
| 12 | u8       | active_image | Currently selected image index |
| 13 | u8       | reserved     | 0 |
| 14 | char[16] | serial       | Hex of the RP2 unique ID, NUL-padded |
| 30 | char[32] | label        | User label, NUL-padded |
| 62 | u8[2]    | padding      | 0 (pads the struct to 64 bytes) |

**Capability bits:**
- Bit 0: Overlay supported (legacy)
- Bit 1: Event notifications supported
- Bit 2: Multi-image supported
- Bit 3: Write-through mode active
- Bit 4: File-level transfer ops supported
- Bit 5: Timestamped MIDI output stream supported
- Bit 6: MIDI input notifications supported
- Bit 7: Safe read-only Akai SCSI discovery supported
- Bit 8: Direct Akai initiator session supported
- Bit 9: Software UF2 bootloader restart supported
- Bit 10: 40 KiB transfer frames supported
- Bit 11: Credit-driven pipelined DATA OUT supported
- Bit 12: Accelerated PIO/DMA DATA OUT supported
- Bit 13: Continuous single-command DATA OUT supported
- Bit 14: Native vendor USB bulk interface supported
- Bit 15: Accelerated native DATA IN supported
- Bit 16: Continuous single-command DATA IN supported
- Bits 17-31: Reserved

### 5.3 CMD_SUBSCRIBE_EVENTS (0x09)

**Request:** `event_mask u16` — bit 0 SCSI reads, bit 1 SCSI writes,
bit 2 overlay-full, bit 3 SD changes, bit 4 SCSI bus reset, bit 5 MIDI input.
**Response:** RSP_PONG (0x81).

### 5.4 CMD_GET_SCSI_STATUS (0x08)

**Request:** (none)

**Response: RSP_SCSI_STATUS (0x87), 18 bytes**

| Offset | Type | Field |
|--------|------|-------|
| 0 | u8 | phase (see below) |
| 1 | u8 | last_command |
| 2 | u32 | last_lba |
| 6 | u16 | last_count |
| 8 | u8 | bus_signals |
| 9 | u8 | transfer_active |
| 10 | u32 | bytes_pending |
| 14 | u16[1] + u8[2] | reserved |

**SCSI Phase Values:** 0x00 BUS_FREE, 0x01 ARBITRATION, 0x02 SELECTION,
0x03 RESELECTION, 0x04 COMMAND, 0x05 DATA_IN, 0x06 DATA_OUT, 0x07 STATUS,
0x08 MESSAGE_IN, 0x09 MESSAGE_OUT.

---

## 6. File-Level Transfer Ops (v2)

The firmware owns the FAT filesystem on the SD card; the host moves whole
files. File names are a fixed **char[32]** field, NUL-padded (so max 31 bytes
of name). Recommended flow for replacing an image the sampler is using:

```
CMD_QUIESCE(1) → open/chunks/commit → CMD_QUIESCE(0) → CMD_EJECT_CYCLE(target)
```

### 6.1 CMD_LIST_FILES (0x20)

**Request:** `start_index u16`

**Response: RSP_ACK**

```
┌────────┬────────┬────────┬──────────────────────────────────────┐
│ status │ total  │ count  │ count × directory entry              │
│ u8     │ u16    │ u16    │ 41 bytes each                        │
└────────┴────────┴────────┴──────────────────────────────────────┘
```

Directory entry (41 bytes):

| Offset | Type | Field |
|--------|------|-------|
| 0  | char[32] | name (NUL-padded) |
| 32 | u32 | sizeLo |
| 36 | u32 | sizeHi |
| 40 | u8 | flags (bit meanings firmware-defined; 0 = regular file) |

The device returns as many entries as fit in its response payload. Legacy
devices use the 4096-byte payload
(`1 + 4 + 41·n ≤ 4096` → max 99 per response). The host pages by repeating the
command with `start_index` = number of entries received so far, until it has
`total` entries.

### 6.2 CMD_FILE_OPEN_WRITE (0x21)

**Request:** `name char[32]` + `total_size u64`

The firmware opens **`<name>.part`** for writing. A failed/abandoned upload
therefore never leaves a truncated file under the final name.

**Response: RSP_ACK** — `status u8`.

### 6.3 CMD_FILE_WRITE_CHUNK (0x22)

**Request:** `offset u32` + `data` (≤ 40956 bytes with capability bit 10)

Offsets must be sequential (each chunk starts where the previous ended). A
retransmitted duplicate of the last chunk (same offset, after a lost ack) must
be acknowledged without double-writing.

**Response: RSP_ACK** — `status u8`.

### 6.4 CMD_FILE_CLOSE_COMMIT (0x23)

**Request:** (none)

The firmware closes the staged `.part` file and renames it over the final
name (atomic replace).

**Response: RSP_ACK** — `status u8`.

### 6.5 CMD_FILE_READ_OPEN (0x24)

**Request:** `name char[32]`

**Response: RSP_ACK** — `status u8` + `size u64`.

### 6.6 CMD_FILE_READ_CHUNK (0x25)

**Request:** `offset u32` + `length u16` (≤ 4089)

**Response: RSP_ACK** — `status u8` + `data` (≤ length bytes; short only at EOF).

### 6.7 CMD_EJECT_CYCLE (0x30)

**Request:** `target u8`

Pulses a fixed-disk eject/reinsert cycle so the sampler notices the medium
changed and re-mounts it. The bundled Blaster protocol-v2 firmware interprets
`target` as the SCSI ID. Some earlier v2 variants interpret it as the
zero-based active-image slot. For v2 compatibility, hosts should try the SCSI
ID first and retry once with `active_image` only after `ERR_IMAGE_INDEX`.
Protocol v3 interprets it as the SCSI ID.

**Response: RSP_ACK** — `status u8`.

### 6.8 CMD_QUIESCE (0x31)

**Request:** `on u8` (1 = pause firmware SCSI-side activity, 0 = resume)

**Response: RSP_ACK** — `status u8`.

---

## 7. MIDI Transport (v3, optional)

MIDI is a separate real-time route from bulk sample/program file transfer. A
device must advertise capability bit 5 before accepting output and bit 6 before
sending input. A host must keep another MIDI route (normally CoreMIDI) when
these bits are absent.

### 7.1 CMD_MIDI_SEND_BATCH (0x40)

Payload:

```
u8 port | u8 flags | u16 event_count |
repeat event_count { u32 timestamp_offset_us | u16 length | u8 data[length] }
```

- flag bit 0 requests immediate dispatch;
- flag bit 1 indicates that the batch contains SysEx;
- timestamps are microsecond offsets from batch dispatch;
- each event contains one MIDI 1.0 channel/system message or complete SysEx.

Response: `RSP_ACK` with `u8 status`, `u16 accepted_count`, and
`u16 queue_depth`.

### 7.2 CMD_MIDI_FLUSH (0x41)

Request: `u8 port`. Response: status-only `RSP_ACK`.

### 7.3 NOTIFY_MIDI_INPUT (0xE7)

Uses the same batch payload as `CMD_MIDI_SEND_BATCH`. It is emitted only when
the host subscribed to event-mask bit 5 and input capability bit 6 is present.

---

## 8. Read-Only Akai Discovery (v3, optional)

This command is a safety gate for later direct-to-RAM work; it does not alter
sampler memory, programs, samples, or the SD card. Capability bit 7 is the only
valid indication that a device supports it. Protocol version, USB product name,
and the presence of initiator APIs are not sufficient.

### 8.1 CMD_AKAI_DISCOVER (0x50)

Request: `u8 target_id | u8 initiator_id`.

- `target_id` is 0–7, or `0xFF` to scan all IDs other than the initiator;
- `initiator_id` is 0–7 and conventionally 7 for ZBridge;
- the two IDs must differ when a target is explicit;
- the firmware may issue only TEST UNIT READY and INQUIRY;
- before responding, firmware must wait for BUS FREE, complete the bounded
  initiator operation, and release the bus on every exit path;
- any inability to guarantee that cleanup fails closed and must leave
  capability bit 7 clear.

### 8.2 RSP_AKAI_DEVICE (0x90)

Exactly 32 bytes, derived from the standard INQUIRY response:

| Offset | Type | Field |
|--------|------|-------|
| 0 | u8 | discovered target ID |
| 1 | u8 | ZBridge initiator ID used |
| 2 | u8 | peripheral device type |
| 3 | u8 | ANSI version |
| 4 | char[8] | vendor, space padded |
| 12 | char[16] | product, space padded |
| 28 | char[4] | revision, space padded |

For the recommended S3200XL Direct RAM setup, the sampler's local processor
target is 6 and its remote-computer/ZBridge initiator ID is 7. The dedicated
initiator firmware does not simultaneously present HD5.

### 8.3 Direct session and native bulk operations (v4-v9, optional)

`CMD_AKAI_SESSION_BEGIN` carries `target_id u8 | initiator_id u8` and returns
the 36-byte standard INQUIRY data in `RSP_ACK`. `CMD_AKAI_SCSI_EXECUTE` carries
`direction u8 | cdb_length u8 | timeout_ms u16 | expected_read_length u32 |
outbound_length u32 | cdb | outbound_data`; its ACK reports SCSI status/sense
and any bounded read data. `CMD_AKAI_SESSION_END` has no payload.

Continuous DATA OUT begins with exact byte/chunk counts, then uses either
sequence-numbered 4 KiB CDC credits or the negotiated native USB OUT endpoint.
FINISH does not acknowledge until accepted, consumed, and SCSI-completed counts
agree. Continuous DATA IN begins with an exact even byte count, acknowledges
the native endpoint negotiation, streams bytes over vendor USB IN, and requires
a FINISH status/checksum agreement. ABORT and disconnect paths release the SCSI
PHY. Hosts must use only explicitly advertised capability combinations.

---

## 9. Error Handling

### 9.1 Error Response Format

**RSP_ERROR (0x8F):**
```
┌─────────────────┬─────────────────┬─────────────────────────────────┐
│ error_code      │ context         │ message                         │
│ 1 byte          │ 1 byte          │ 0-60 bytes (null-terminated)    │
└─────────────────┴─────────────────┴─────────────────────────────────┘
```

### 9.2 Error Codes

| Code | Name | Description |
|------|------|-------------|
| 0x01 | ERR_INVALID_COMMAND | Unknown opcode |
| 0x02 | ERR_INVALID_LENGTH | Payload size mismatch |
| 0x03 | ERR_CRC_MISMATCH | CRC verification failed |
| 0x04 | ERR_INVALID_LBA | LBA out of range |
| 0x05 | ERR_BLOCK_COUNT | Invalid block count |
| 0x06 | ERR_OVERLAY_FULL | RAM overlay at capacity |
| 0x07 | ERR_SD_READ | SD card read error |
| 0x08 | ERR_SD_WRITE | SD card write error |
| 0x09 | ERR_NO_SD | SD card not present |
| 0x0A | ERR_SCSI_BUSY | SCSI transfer in progress |
| 0x0B | ERR_NO_IMAGE | No disk image loaded |
| 0x0C | ERR_IMAGE_INDEX | Invalid image index |
| 0x0D | ERR_TIMEOUT | Operation timed out |
| 0x0E | ERR_INTERNAL | Internal firmware error |
| 0x0F | ERR_FILE_NOT_FOUND | File does not exist (v2) |
| 0x10 | ERR_FILE_STATE | File op out of sequence / bad offset (v2) |
| 0x11 | ERR_MIDI_UNAVAILABLE | No concrete MIDI adapter is available |
| 0x12 | ERR_MIDI_QUEUE_FULL | Adapter rejected an event because its queue is full |
| 0x13 | ERR_INVALID_MIDI | Malformed or truncated MIDI batch |
| 0x14 | ERR_AKAI_NOT_FOUND | No compatible Akai processor target answered |
| 0x15 | ERR_SCSI_ID_CONFLICT | Target and initiator IDs are not unique |
| 0x16 | ERR_ROLE_HANDOFF_FAILED | Firmware could not guarantee the safe role handoff |

### 9.3 Recovery Procedures

**CRC Error:** retransmit the command once; on repeated failure, surface the
error (host may reset the connection).

**Lost ack on a file chunk:** retransmit the chunk once after the timeout —
offsets make it idempotent.

**Overlay Full (legacy):** CMD_SYNC_TO_SD or CMD_CLEAR_OVERLAY, then retry.

**SCSI Busy:** wait for BUS_FREE (poll CMD_GET_SCSI_STATUS ≤ 10/sec or use
notifications), or use CMD_QUIESCE around the transfer.

---

## 9. Legacy: LBA Access + RAM Overlay (optional)

> **Status: legacy/optional.** This was v1's primary mechanism. It is retained
> for diagnostics and raw image inspection, but the file-level ops of section 6
> are the supported transfer path — nothing host-side can safely allocate LBAs
> inside a live Akai filesystem, so raw writes are only meaningful for
> whole-image tooling.
>
> Firmware may omit the overlay entirely (capability bit 0 = 0), in which case
> the overlay-dependent commands return ERR_INVALID_COMMAND.

### 9.1 CMD_READ_BLOCKS (0x03)

**Request:** `start_lba u32` + `block_count u16` (1–**7**)
**Response: RSP_BLOCK_DATA (0x83):** `start_lba u32` + `block_count u16` + data (count × 512).
Reads check the RAM overlay first, then the SD card.

### 9.2 CMD_WRITE_BLOCKS (0x04)

**Request:** `start_lba u32` + `block_count u16` (1–**7**) + data (count × 512)
**Response: RSP_ACK/RSP_WRITE_ACK (0x84):** `start_lba u32` + `block_count u16` + `overlay_used u16` (v1 layout, no status byte).
Writes land in the RAM overlay, not directly on SD.

### 9.3 CMD_SYNC_TO_SD (0x05)

**Request:** `flags u8` (bit 0 clear-after, bit 1 verify)
**Response: RSP_SYNC_COMPLETE (0x85):** `status u8` + `blocks_written u16` + `errors u16`
(status 0 success, 1 partial, 2 failure).

### 9.4 CMD_GET_DIRTY_BLOCKS (0x06)

**Request:** `filter u8` (0 all, 1 Mac-written, 2 Akai-written) + `max_count u16`
**Response: RSP_DIRTY_BLOCK_LIST (0x86):** `total_count u16` + `returned_count u16` + LBA list (u32 each).

### 9.5 Overlay behavior

The RAM overlay is a write-back cache (256 × 512-byte entries, ~128KB+2KB
metadata). Reads (SCSI or USB) hit the overlay first. Mac writes are stored
dirty (not written through); Akai writes are stored and written through to SD,
with NOTIFY_BLOCKS_WRITTEN if subscribed. When full, the device sends
NOTIFY_OVERLAY_FULL and returns ERR_OVERLAY_FULL until the host syncs or
clears. Entry flags: bit 0 VALID, bit 1 DIRTY, bit 2 FROM_MAC, bit 3 FROM_AKAI.

### 9.6 Notification payloads

**NOTIFY_SCSI_COMMAND (0xE1):** `command u8` + `lba u32` + `block_count u16` + `flags u8`.
**NOTIFY_BLOCKS_WRITTEN (0xE2):** `start_lba u32` + `block_count u16`.

---

## 10. Timing Constraints

### 10.1 SCSI Timing

| Phase | Timeout |
|-------|---------|
| Selection | 250ms |
| Command | 10ms |
| Data transfer | Continuous (no pause) |
| Status | 10ms |

**Implication:** USB operations must not block SCSI handling. The main loop
services both, but SCSI takes priority during active transfers. Use
CMD_QUIESCE(1) for long file transfers when the sampler can be paused.

### 10.2 USB Timing

| Operation | Expected Time |
|-----------|---------------|
| Ping/Pong RTT | < 5ms |
| Read/write 1 block | < 10ms |
| Read/write 7 blocks | < 50ms |
| File chunk (40956 B) | Device/SD dependent; host timeout 5 s |
| Sync to SD | Variable |

Host default command timeout: 5 s (60 s for CMD_SYNC_TO_SD).

### 10.3 Recommended Practices

1. **Batch:** fill chunks/blocks to the maximum per command
2. **Poll sparingly:** don't poll CMD_GET_SCSI_STATUS more than 10/sec
3. **Use events:** subscribe to notifications instead of polling
4. **Quiesce for big uploads:** CMD_QUIESCE around image replacement, then CMD_EJECT_CYCLE

---

## 11. Implementation Notes

### 11.1 Firmware Integration Points

**Main Loop (ZuluSCSI.cpp):**
```c
void zuluscsi_main_loop() {
    platform_reset_watchdog();
    platform_poll();

    // Service USB when SCSI is idle (always, when quiesced)
    if (scsiDev.phase == BUS_FREE || usb_bridge_quiesced()) {
        usb_bridge_poll();
    }

    scsiPoll();
    // ... rest of loop
}
```

### 11.2 Thread Safety

The RP2350 is single-core for ZuluSCSI purposes (second core reserved for PIO).
All operations are cooperative. USB callbacks may fire during any code; use
volatile for shared state and keep critical sections short.

### 11.3 Host (Swift) Receive Path

The reference host implementation (ZBridge Swift package) uses exactly ONE
reader: a serial queue drains the port, runs an incremental frame parser
(section 3.6 resync rules), and routes frames — responses to the single
pending-command continuation, notifications to the delegate. Commands are
stop-and-wait with one retransmission on CRC failure.

---

## Appendix A: Akai Disk Format Reference

### A.1 Block Layout

| Block | Content |
|-------|---------|
| 0 | Partition table header |
| 0-2 | FAT (block allocation) |
| 3 | Volume directory start |
| 4+ | File data |

### A.2 Partition Table (Block 0)

| Offset | Size | Description |
|--------|------|-------------|
| 0x00 | 2 | Disk size / 2 (in MB) |
| 0x02 | 192 | Unknown/scramble table |
| 0xC8 | 2 | Partition marker (0x2F00) |
| 0xCA | 12 | Partition A name |
| 0xD6 | 2 | Partition A type + LUN |
| 0xD8 | 16 | Volume list entries... |

### A.3 Sample Header (150 bytes)

| Offset | Size | Description |
|--------|------|-------------|
| 0x00 | 2 | Type (0x0301 = S1 sample) |
| 0x02 | 1 | Root note (MIDI) |
| 0x03 | 12 | Name (Akai encoding) |
| 0x0F | 1 | Flags (0x80) |
| 0x10 | 1 | Valid flag (0x01) |
| 0x16 | 2 | Sample index |
| 0x1A | 4 | Length (samples, LE) |
| 0x22 | 4 | Loop end |
| 0x2C | 4 | Length copy |
| 0x30 | 2 | Unknown (9999) |
| 0x88 | 4 | Sample rate marker |
| 0x96 | - | Audio data |

---

## Appendix B: Protocol Examples

### B.1 Connection Sequence

```
Mac                          ZuluSCSI
 │──── CMD_GET_INFO ───────────►│
 │◄─── RSP_DEVICE_INFO (64B) ───│
 │──── CMD_SUBSCRIBE(0x001F) ──►│
 │◄─── RSP_PONG ────────────────│
```

### B.2 File Upload (v2)

```
Mac                          ZuluSCSI
 │──── CMD_QUIESCE(1) ─────────►│
 │◄─── RSP_ACK(0) ──────────────│
 │──── CMD_FILE_OPEN_WRITE ────►│  ("DRUMS.HDS", 8MB) → opens DRUMS.HDS.part
 │◄─── RSP_ACK(0) ──────────────│
 │──── CMD_FILE_WRITE_CHUNK ───►│  (offset 0, up to 40956 B)
 │◄─── RSP_ACK(0) ──────────────│
 │            ... repeat with sequential offsets ...
 │──── CMD_FILE_CLOSE_COMMIT ──►│  → rename DRUMS.HDS.part → DRUMS.HDS
 │◄─── RSP_ACK(0) ──────────────│
 │──── CMD_QUIESCE(0) ─────────►│
 │◄─── RSP_ACK(0) ──────────────│
 │──── CMD_EJECT_CYCLE(target) ─►│  → sampler re-mounts the image
 │◄─── RSP_ACK(0) ──────────────│
```

### B.3 Retransmission on CRC failure

```
Mac                          ZuluSCSI
 │──── CMD_FILE_WRITE_CHUNK ───►│
 │◄─── RSP_ACK (corrupted) ─────│   host CRC check fails
 │──── CMD_FILE_WRITE_CHUNK ───►│   same offset (idempotent), once
 │◄─── RSP_ACK(0) ──────────────│
```

---

*End of Specification*

## Build 53: persistent boot-role selection (candidate)

Protocol remains 9. Capability bit 17 gates software boot-mode commands.
GET_INFO reserved byte 13 reports current mode: 0 = SD disk, 1 = Direct RAM.
`0x34 GET_BOOT_MODE` takes no payload; ACK body is `[active, saved]`, with
saved 255 meaning no valid override (physical switch controls boot).
`0x33 SAVE_BOOT_MODE` takes one byte, 0 or 1. It refuses an active direct session,
file transfer, quiesce, or non-free SCSI phase. Success means the 8-byte record
was written, synced, committed, and read back. It does not change the active role.
Power-cycle the board and sampler after saving; USB power must also be removed.

The SD root `zbridge-mode.dat` record is `ZBM1`, one mode byte, zero reserved
byte, then CRC16-CCITT-FALSE over the first six bytes, little-endian. Missing or
invalid records preserve physical-switch selection. Remove the file to restore
switch control. Settings travel with the SD card. A temporary `.tmp` file is
synced before replacement; interruption during replacement can lose the override,
which safely returns to switch selection rather than guessing a mode.

Role is loaded before `platform_late_init`, including native initiator GPIO
setup for Direct RAM. The compile-time force-on is removed. SD mode withholds
Direct RAM/MIDI capability bits and rejects discovery/session start. Native
initiator disk imaging stays disabled. Software bootloader is available in both
roles. Build 52 bulk read/write paths are retained. Hardware verification remains
pending; compilation alone is not an SD/playback or Direct RAM result.
