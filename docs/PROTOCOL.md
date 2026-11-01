# MINI-5 Bluetooth programming protocol

Everything below was confirmed by matching this app's output byte for byte against reference frames
produced by the documented JavaScript implementation (K4RJM's Ham-Rx CPS). It is the wire truth the
Swift code implements.

## Link

| Item | Value |
| --- | --- |
| Service | `FFE0` |
| Characteristic | `FFE1` (write **and** notify, same handle) |
| Notifications | required before any command |
| Response timeout | 4 s per reply |

Writes go out as `writeWithoutResponse` when offered (the vendor app does this), otherwise
`writeWithResponse`. 132-byte write frames fit in one LE packet at the negotiated MTU.

## Handshake

| Step | Send | Expect | Meaning |
| --- | --- | --- | --- |
| 1 | `PROGRAMCOLORPROU` (16 bytes ASCII) | `06` | hello |
| 2 | `46` | 16 bytes | config block |
| 3 | `4D` | 15 bytes | identity; first 8 = `5RMINI ` |
| 4 | `53 45 4E 44 21 05 0D 01 01 01 04 11 08 05 0D 0D 01 11 0F 09 12 09 10 04 00` | `06` | start session ("SEND!" + params) |

Refuse to continue if the identity is not `5RMINI`.

## Reading

Request 64 bytes at a time from a 64-byte-aligned address:

```
send:     52 <addrHi> <addrLo> 40
receive:  52 <addrHi> <addrLo> 40 <64 data bytes>      (68 bytes total)
```

Read map — 521 blocks, concatenated in this order gives the 33,344-byte image:

| Address range | Size | Image offset |
| --- | --- | --- |
| `0x0000 - 0x803F` | `0x8040` | `0x0000` |
| `0x9000 - 0x903F` | `0x40` | `0x8040` |
| `0xA000 - 0xA1BF` | `0x1C0` | `0x8080` |

Finish with `45`.

## Writing

128-byte payloads, `0xFF`-padded at the end of each region:

```
send:  57 <addrHi> <addrLo> 80 <128 data bytes>      (132 bytes total)
ack:   06
```

| Address range | Size | Blocks |
| --- | --- | --- |
| `0x0000 - 0x803F` | `0x8040` | 257 (last padded 64) |
| `0x9000 - 0x903F` | `0x40` | 1 (padded 64) |
| `0xA000 - 0xA1BF` | `0x1C0` | 4 (last padded 64) |

262 blocks total. Byte `0x9022` must be `1` or the radio disables Bluetooth programming.

## Byte obfuscation

Every byte in the CPS image is transformed with a repeating 4-byte key `43 4F 20 37` ("CO 7"),
indexed by image offset `% 4`:

```
k = key[offset % 4]
if k == 0x20                          -> leave the byte alone
else if byte in {00, FF, k, k ^ FF}   -> leave the byte alone
else                                  -> byte ^= k
```

The transform is its own inverse, so the same function encodes and decodes.

## Channel records

1000 slots × 32 bytes at offset `slot * 32`. Slots 1–999 are usable; record 1000 is reserved and
must stay `0xFF`.

| Bytes | Meaning |
| --- | --- |
| 0–3 | receive frequency, BCD nibble pairs, big-endian order (byte 3 holds the first two digits) |
| 4–7 | transmit frequency, same encoding; all `FF` = receive only |
| 8–9 | receive tone, little-endian 16-bit |
| 10–11 | transmit tone, same |
| 12 | DTMF signal group (0–19) |
| 13 | PTT ID mode (0–3) |
| 14 | transmit power (0 high, 1 low) |
| 15 | bit 6 bandwidth, bit 4 squelch mode, bit 3 busy lock, bit 2 scan, bit 0 FHSS |
| 16–19 | unused |
| 20–31 | name, GBK, `FF`-terminated, max 12 bytes |

Frequency encoding: `146.52000` → digits `14652000` → pairs `00 20 65 14` (every nibble is a decimal
digit, so `0x14` means "one, four").

Tone encoding: index 0 = OFF; 1–50 = CTCSS stored as `round(Hz * 10)` little-endian; 51+ =
DCS stored as `index - 50` little-endian.

## The trailing gap

Offsets `0x7D00–0x7FFF` are not channels. The factory CPS mirrors the final 64 bytes of channel data
(two records) across it, alternating a transformed copy with the plain copy, 12 blocks of 64:

```
pair = image[0x7CC0..0x7D00]
for i in 0..<12: image[0x7D00 + i*64] = (i even) ? crypt(pair) : pair
```

This app reproduces that exactly rather than guessing.

## Settings block (`0x9000`, 64 bytes)

Named offsets inside the block:

| Offset | Field |
| --- | --- |
| 0 | squelch (0–9) |
| 1 | battery save |
| 2 | VOX level |
| 3 | backlight |
| 4 | dual watch |
| 5 | transmit time limit |
| 6 | keypad beep |
| 7 | spoken prompts |
| 8 | language |
| 9 | side tone |
| 10 | scan resume mode |
| 11 | VFO PTT ID mode |
| 12 | PTT ID delay |
| 13 / 14 | A / B display mode |
| 15 | VFO busy lock |
| 16 | automatic keypad lock |
| 17 / 18 | alarm mode / alarm tone |
| 20 / 21 / 22 | tail clear, repeater tail clear, repeater tail detect |
| 23 | end-of-transmission beep |
| 25 | FM broadcast receiver |
| 26 | A work mode (low nibble) + B work mode (high nibble) |
| 27 | keypad lock |
| 28 | power-on display |
| 29 | repeater access tone |
| 32 / 33 | VOX delay, menu exit delay |
| 34 (`0x22`) | wireless CPS enable — **must be 1** |
| 40 | transmit timeout warning |
| 43 | tone scan mode |
| 44–45 | VFO scan low, little-endian |
| 46–47 | VFO scan high, little-endian |
| 50 | side-key short press |
| 55 | reset menu |
| 57 | DTMF call hold time |
| 58 | VOX switch |

## VFO blocks (`0x8000` A, `0x8020` B, 32 bytes each)

| Bytes | Meaning |
| --- | --- |
| 0–7 | frequency as one decimal digit per byte (`146.52000` → `1 4 6 5 2 0 0 0`) |
| 8–9 / 10–11 | receive / transmit tone |
| 13 | busy lock |
| 14 | offset direction (high nibble) + DTMF group (low nibble) |
| 16 | transmit power |
| 17 | bit 6 bandwidth, bit 0 FHSS |
| 19 | tuning step |
| 20–26 | offset as 7 decimal digits (`005.0000` → `0 0 5 0 0 0 0`) |
| 27 | squelch mode |

Known factory quirk: VFO B takes its final offset digit from VFO A. The app reproduces it so that
read → edit → write is stable.

## DTMF block (`0xA000`, 448 bytes)

| Bytes | Meaning |
| --- | --- |
| 0–2 | own ID, 3 digits |
| 7 / 8 | tone duration / pause duration |
| 9 | separator |
| 10 | group call code |
| 32 + i*16 (0 ≤ i < 20) | group i: 3 digit bytes, then a 10-byte GBK name at +5 |
| 384–399 | transmit start code, 16 digits |
| 400–415 | transmit end code, 16 digits |

Digits are nibbles into `0123456789ABCD*#`.

## Notes for future work

- Channel 1000 is reserved; the app never offers it.
- The identity step returns 15 bytes; only the first 8 are compared.
- The vendor app sends `45` when a read finishes. Skipping it works on read but sends nothing on
  write — do not invent a post-write command.
- If a read stalls mid-way, the link is already dead: disconnect and reconnect rather than retrying
  the block, which is what the reference implementation does too.
