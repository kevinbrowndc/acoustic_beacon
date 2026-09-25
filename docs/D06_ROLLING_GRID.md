# D06 rolling observation / timing-grid decoder

## Why this change

The reported D05 physical trial had 393 accepted burst symbols, zero preambles, and a closest burst-derived preamble 9/32 bits wrong. D06 stops using those burst decisions to decode frames. D05 burst measurements and history remain available as an independent diagnostic observer; no new local splitting rule is added.

## Algorithm

The existing microphone conversion and 240-sample Hann/Goertzel frequency analysis remain unchanged. Every 5 ms block contributes the two configured frequency amplitudes to a bounded ring of cumulative observations if it passes the existing amplitude and confidence gates. Noncandidate blocks advance time but add no evidence.

For the configured 80 ms symbol, the ring retains 546 observations (2,730 ms), enough for the 32-bit preamble and alignment lookahead. It contains frequency evidence, not recorded PCM. Prefix sums let each candidate slot aggregate all evidence between its start and end without rescanning the individual bursts.

Every 5 ms, the receiver evaluates the last 32 consecutive 80 ms slots. Moving this window by 5 ms searches the 16 timing phases within one 80 ms symbol and slides the preamble across successive symbol positions. Fractional endpoint interpolation handles other already-supported configured durations without rounding the symbol period to a number of hops.

Each slot selects the frequency with greater summed amplitude. It requires at least the existing minimum evidence duration (20 ms for this profile, accumulated across the slot) and the unchanged 0.75 dominance/confidence threshold. The existing per-block amplitude threshold 0.008 also remains. Fragmented evidence can therefore contribute to a slot without requiring an uninterrupted burst; repeated same-frequency symbols can occupy successive slots without any quiet gap or transition.

All 32 bits must exactly match D3 91 A6 5C / 11010011100100011010011001011100. Hamming distance is diagnostic only: a nonzero distance never locks. After the first exact hit, the receiver examines one additional symbol interval to compare nearby exact alignments. It ranks them by summed slot purity; a small first-half energy preference breaks near ties using the existing 40 ms tone / 40 ms silence shape. This preference does not change the validation gates.

The chosen alignment is locked at the matched preamble. Subsequent slots advance by exactly 80 ms. Header version 1, length 1–64, UTF-8 decoding, CRC16/CCITT-FALSE and two matching frames remain required. Missing/ambiguous slots or invalid headers abandon that lock; a complete frame is passed to the unchanged codec and repeat validator. There is no inserted bit, fuzzy preamble acceptance, CRC repair or payload substitution. Frame data are consumed incrementally, so even maximum-length frames do not require an ever-growing audio buffer.

The timing phase is fixed during a frame. The change does not implement sample-clock drift tracking or guarantee recovery when insufficient evidence remains in a slot. Physical acceptance is still pending.

## Diagnostics

The existing Beacon Debug screen now begins with D06 TIMING GRID:

- Rolling observation count/capacity and duration.
- Best timing offset in milliseconds, modulo the symbol period relative to listening start.
- Best complete candidate preamble and Hamming distance.
- Whether timing lock was ever achieved, lock count, and current lock state.
- Last locked offset and the recovered exact preamble.
- Missing locked slots and last unlock reason.
- CRC-valid decoded payload, CRC state and valid-frame count.

The D05 burst summary, first/latest/closest history, acceptance counts, transition counts, and reset reasons are retained below and explicitly labeled observational. They cannot reset the D06 grid or deliver a beacon. Stop preserves the diagnostics; Start or Apply creates a fresh detector as before. No microphone recording, permission, navigation, or unrelated content behavior was added.

## Automated evidence

All 42 existing tests passed immediately after connecting the new grid path. The complete suite now has 52 passing tests. Static analysis is clean after four brace-only formatting corrections.

New cases cover:

- Fragmented observations: 5 ms tone fragments with 10 ms holes across each unchanged 80 ms bit slot.
- Joined observations: uninterrupted full-slot tones, including adjacent identical bits with no quiet or frequency boundary.
- Mixed fragmented/joined slots.
- All three shapes at offsets of 0, 71, 239, 769, 2003 and 3777 samples, using varied callback sizes including sub-hop and odd sizes. Every trial recovers three exact preambles, three CRC-valid frames, wookiemeat and one two-frame-validated event.
- Recording begins partway through a symbol within the first preamble: the next two frames are recovered.
- One deliberately incorrect preamble bit: Hamming distance 1, zero timing locks, zero accepted frames.
- Corrupted CRC and single-frame inputs retain their rejection behavior.
- Invalid headers release the lock without delivering a payload.
- A missing locked slot abandons the first frame and reacquires the following two.
- A 64-byte payload decodes beyond the rolling-buffer length.
- Ten minutes of idle observations leave the ring bounded at 546 observations with no lock.

The original exact-WAV test still runs the actual PCM bytes through production MicrophoneCapture conversion and BeaconDetector at arbitrary chunk/sample alignment. Its result remains three preambles, three CRC-valid frames, payload wookiemeat. Existing noise, continuous carrier, echo, D05 joined-pair, diagnostic and UI tests also pass.

These received-path fixtures are controlled tests of the reported failure class, not a recording of the physical phone.

## Unchanged delivery WAV

Acoustic-Beacon-D06-audible.wav is generated by the unchanged tool, byte-identical to the prior audible stimulus: 4000/5000 Hz, 48 kHz mono PCM16, 80 ms symbols, 40 ms tone/40 ms silence, unchanged preamble/header/payload/CRC, wookiemeat, three frames, 36.56 seconds.

SHA256: 6f4d14899f12da6931283e7b1f3ffd24d48bdf7e5b299751d4eaac6216956caf.

Reproduce from the application directory:

    dart run tool/generate_beacon.dart --audible --output=../Acoustic-Beacon-D06-audible.wav
    flutter test --no-pub --dart-define=BEACON_TEST_WAV=../Acoustic-Beacon-D06-audible.wav

The delivery APK is Acoustic-Beacon-D06-diagnostic.apk, version 1.0.0 (6). Build/signature verification is recorded separately with the delivery logs and checksum.
