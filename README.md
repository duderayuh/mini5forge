# MINI-5 Forge

A local macOS app that programs the **Baofeng MINI-5** (the Bluetooth-only sibling of the UV-5R)
without the vendor phone app. No account, no cloud, no region lock — it talks to the radio directly
over Bluetooth LE from your Mac.

A native macOS CPS for the Baofeng MINI-5 / UV-5R Mini family. `build.sh` builds the app and installs it to `$HOME/Applications`.

---

## Why this exists

The MINI-5 has no programming cable. Everything goes over Bluetooth LE to an app that has been
region-limited, which leaves a US owner with a radio they can't reprogram. This app speaks the same
wire protocol the vendor software does, but runs entirely on the Mac.

## Using it

1. Power the radio on and keep it near the Mac.
2. **Connect** → pick the radio in the list (it advertises service `FFE0`; the name usually contains
   `5RMINI` or `MINI`). If nothing shows up in 6 seconds the app falls back to listing every nearby
   BLE device so you can identify it manually.
3. **Read** pulls all 33,344 bytes of CPS data: 999 channels, general settings, both VFO registers,
   and DTMF.
4. Edit. The **Channels** table edits in a sheet (frequency, name, tones, power, bandwidth, scan,
   busy lock, PTT ID, DTMF group). **Settings**, **VFO** and **DTMF** panes cover the rest.
5. **Write** shows exactly how many bytes change and where, then asks for one acknowledgement.
6. After writing it re-reads the whole radio and diffs it byte for byte against what it intended.
   Green "verified on radio" in the status bar means the bytes match.

**Always read first.** Editing a document built from factory defaults and writing it replaces the
radio's real settings with defaults. File ▸ Save pre-flight backup keeps the original image.

Backups are Ham-Rx / Mini 5 Studio compatible (`.img`, 33,344 bytes plus the `UV-5R Mini` trailer),
so they can be opened in the browser CPS as well.

### CSV

File ▸ Import channels from CSV accepts comma, semicolon or tab separated files with a header row.
Recognised columns include name/callsign, RX/frequency, TX, offset + duplex, tone / rx_tone /
tx_tone, power, bandwidth and scan. It replaces channels from slot 1 and clears the rest; settings
and VFOs are untouched. Export writes the app's own column set.

## Safety rails

- Write is disabled until a document is loaded and something actually changed.
- Frequencies are validated as `###.#####` on a MHz grid before any bytes are built.
- Names are validated as GBK, max 12 bytes — the radio will not store more.
- The `0x9022` "wireless CPS enabled" flag is forced to 1 on every write; if that byte lands as 0 the
  radio stops accepting Bluetooth programming.
- A failed or ambiguous write is never retried automatically. The app disconnects and tells you.
- Nothing is written until every block is validated in memory.

It is a handheld transceiver: programming it does not grant permission to transmit. Stay inside the
service you are licensed for (amateur, GMRS, MURS, Part 90 as applicable).

## Layout of the source

```
Sources/Mini5Core/Radio/     image container, obfuscation, codec, tone + option tables
Sources/Mini5Core/BLE/       CoreBluetooth transport (RadioLink.swift) and the wire protocol
Sources/Mini5Core/Support/   CSV import/export
Sources/Mini5Forge/UI/       SwiftUI panes
Sources/Mini5Forge/App/      model, app entry, headless probe and snapshot helpers
Sources/SelfTest/            byte-exact conformance test against reference captures
Golden/golden.json           reference frames + image produced by the documented JS implementation
```

## Build

```sh
./build.sh                       # -> build/Mini5Forge.app, ad-hoc signed
./build/mini5forge-selftest Golden/golden.json
```

`build.sh` drives `swiftc` directly — SwiftPM is broken on this machine's Command Line Tools
(`swift-package` symbol mismatch against BuildServerProtocol), so there is no Package.swift path
that works here. Don't "fix" that by adding one.

### Diagnostics built into the binary

```sh
# what Bluetooth can see, writes JSON, no radio commands sent
open build/Mini5Forge.app --args --probe --out /tmp/probe.json

# render every pane to PNG without needing screen-recording permission
./build/Mini5Forge.app/Contents/MacOS/Mini5Forge --render /tmp/m5shots
```

## Verification status

- Codec: **byte-identical** to the reference implementation — all 33,344 image bytes and all 262
  write frames match, and decode/encode round-trips byte-stable. See `docs/PROTOCOL.md`.
- Bluetooth: scanning, permissions and CoreBluetooth plumbing verified on this Mac (33 BLE devices
  enumerated from the bundled app).
- Hardware handshake/read/write: **not yet exercised against a physical radio.** The radio was not
  powered on or in range when this was built. First real read is the actual test.

## Provenance and licensing

The wire protocol was recovered from public reverse-engineering work: K4RJM's Ham-Rx browser CPS
(GPLv3), gabe0000's uv5rmini-live protocol notes (GPLv3), and dylanmaniatakes' Android CPS (MIT).
No source code was copied — the Swift here is written fresh — but the tone table, option labels and
memory layout are factual data derived from those projects. Personal use is uncomplicated; **if you
ever publish or distribute this, license it GPLv3** to match the upstream work it depends on.

## Hardware notes (verified on the actual radio)

- The MINI-5 advertises as **`walkie-talkie`** advertising service `FFE0`, roughly -70 dBm at arm's length.
- **The first BLE connection after the radio powers on always drops.** Connect, then reconnect — the
  programmer does this automatically (one retry), and the GUI needs a second Connect click.
- **The radio reboots its Bluetooth stack right after the last write block is acknowledged.** The write
  itself is complete (all 262 ACKs land); the verification read has to happen in a new session.
  Reconnect and read again — `0 byte(s) change` against the plan means the write is confirmed.
- `CBCentralManager` reports `.unknown` on first use, so the first scan request has to be queued and
  replayed when the state turns `.poweredOn`. `RadioLink` does this; don't call `scanForPeripherals`
  directly from a fresh manager.
- Channel capacity is 999 usable records; record 1000 is reserved and must stay `0xFF`.
- **Force-killing processes that hold a live `CBCentralManager` wedges `bluetoothd`.** Symptom: every new
  client reports `.unknown` forever while `system_profiler` still says the controller is `On`, and even
  `blueutil --power` hangs. Fix: toggle Bluetooth off/on in Control Center, or `sudo pkill bluetoothd`
  (launchd respawns it). Then retry — do not keep spawning probe processes, it makes it worse.
- Repeat runs need a short settle between them: one connection attempt per session is normal, and the
  programmer's single auto-reconnect covers the radio dropping the first link.
- **Do not infer a missing demodulator from one silent channel.** Airband AM demod works on this radio;
  a single quiet ATIS/ground frequency proves nothing — verify against live tower traffic before changing
  the channel plan. Removing working channels on a hardware hunch is expensive to undo and worse to explain.

## Disclaimer

Not affiliated with, endorsed by, or supported by Baofeng. Programming a radio rewrites its memory;
a bad write can leave it unusable. This tool always reads the full image first, saves a pre-flight
backup, and verifies by re-reading — but you use it at your own risk, on hardware you own.

You are responsible for operating within the radio regulations that apply to you. Transmitting outside
your licence privileges, or on services the hardware is not certified for (FRS, GMRS, MURS, marine,
public safety), is on you, not on this software.
