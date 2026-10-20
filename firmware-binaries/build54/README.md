# Build 54 — SD disk / Direct RAM, protocol 9

Built from this repository at 3b938d8 (patches 0001–0009 on the pinned
upstream). GET_INFO firmware word 0x36000036. Board: ZuluSCSI Blaster.

| File | SHA-256 |
|---|---|
| ZuluSCSI_Blaster_zbridge_direct_candidate.bin | 66eeb1b2c10c0a5d2058b1e6512a01d32e6983641ef02331b93493514c8f94a4 |
| ZuluSCSI_Blaster_zbridge_direct_candidate.uf2 | 1f860d5615357dc47aa544c445fe037474f025ac00da03c7df8dbeba00084565 |

The UF2 payload is the BIN byte for byte.

Role: the initiator DIP switch selects the role at a cold start (off: SD
disk; on: Direct RAM) unless `zbridge-mode.dat` on the card saves a mode.

Hardware: passed SD boot (image served, sampler loads and plays) and
Direct RAM role selection on an Akai S3200XL, 2026-10-18. Build 53 crashed
in SD mode with a main-stack overflow in `findHDDImages`; build 54 moves its
pathname buffers to static storage (frame 1252 → 212 bytes).

The version banner still reads "Oct 5 2026 21:47:38" (build 53's
timestamp, the version file was not recompiled); identify the build by the
GET_INFO firmware word.
