# D05 frequency-transition segmentation

## Evidence and scope

D04 phone photos show rejected long bursts containing consecutive candidate votes at both configured frequencies, including an approximately 125 ms burst with 1s then 0s. These are receiver diagnostics, not a recording of phone PCM. D05 adds a second boundary source; it does not increase the maximum burst duration, alter the transmitter or claim physical success before retesting.

## Exact algorithm

1. Analyze the same 240-sample (5 ms) blocks. Amplitude 0.008 and confidence 0.75 remain the candidate gates for the audible profile.
2. Keep the current segment's zero/one votes and majority. A possible transition is considered only once that segment has at least the existing minimum candidate duration (20 ms for 80 ms symbols).
3. When a candidate block favors the opposite frequency, temporarily buffer it instead of immediately adding it to the old segment. A second consecutive qualifying opposite-frequency block confirms a stable change (10 ms evidence).
4. Close the old segment at the start of that buffered run. Apply the unchanged 20–70 ms duration limits. Send an accepted old segment to the existing bit/framing/CRC logic; reject an overlong one exactly as before.
5. Start the new segment with BOTH buffered blocks and their original sample timestamps. Neither block is lost or counted twice. Boundary confirmation therefore adds 10 ms latency but does not move the recorded boundary or change the transmitted symbol clock.
6. A return to the original frequency or a noncandidate block before confirmation flushes the unconfirmed block into the original segment. It does not create an extra symbol.
7. Two consecutive noncandidate blocks still close a segment through the original quiet-gap path. Idle timeout, short-burst behavior, header parsing, sync, CRC and repeated matching frames are preserved.

A frequency boundary does not require a quiet gap. It also does not infer the number of repeated same-frequency symbols inside one sustained carrier. A 125 ms constant carrier is still rejected, and a 75 ms run followed by a 50 ms opposite run is split but the 75 ms segment remains LONG. This is intentional compliance with the unchanged 70 ms limit; recovering that overlong segment would require a separately justified change.

The retained debug log now marks each completed segment's boundary as frequency or quiet. Frequency-boundary totals are shown in the existing session totals. No unrelated UI or content behavior changed.

## Tests

Before changing D04, the new test file produced 6 failures and 2 passes: merged runs did not split and WAV-derived joined-tone frames could not recover a preamble. The final file contains 9 cases:

- 65 ms at 5000 Hz plus 60 ms at 4000 Hz (125 ms uninterrupted candidate): two accepted symbols [1,0], lengths [65,60], preceding gap for second symbol 0, one frequency boundary, all 25 candidate blocks conserved.
- Reverse [0,1] transition likewise separates correctly.
- D04-like 15 one votes plus 10 zero votes (75+50 ms): two separate segments, first LONG and second ACCEPT; no increase to maximum duration.
- 125 ms at one frequency: remains LONG, no manufactured boundary.
- One opposite 5 ms block within a valid tone: no extra symbol.
- One opposite block immediately before silence: flushed once, no sample loss or duplication.
- Start with the actual delivered WAV PCM. In a simulated received copy, replace adjacent opposite-symbol pairs with 65+60 ms joined runs and 35 ms trailing silence, preserving each pair's 160 ms extent and all encoded bits. At sample offsets 0, 71 and 239, delivered in 997-sample chunks, recover 3 preambles, 3 CRC-valid frames, payload wookiemeat and one validated event.
- The same received-path fixture with a payload bit changed but original CRC: 3 preambles, 3 CRC failures, zero accepted frames/events.
- Only one such frame: one CRC-valid frame, zero validated events.

The joined-run fixture is a controlled model of the observed missing-boundary condition, not a claim to reproduce every distortion in the physical recording. The transmitted delivery WAV is not changed by the fixture.

All 42 tests in the complete suite passed using the actual D05 delivery WAV path. This includes the existing exact-file WAV audit through production microphone byte conversion, clean quiet-gap decoding, echo tests, invalid/noisy input, UI tests and diagnostic retention tests. The old diagnostic test's mixed 50+50 ms example was changed to a true 100 ms constant tone, because mixed valid runs are now deliberately segmented; the new transition tests cover the mixed case explicitly. Static analysis reports no issues.

## Preserved protocol and matching stimulus

4000 Hz = 0; 5000 Hz = 1; 48 kHz mono PCM16 little-endian; MSB-first; 80 ms transmitted symbols with 40 ms tone and 40 ms silence; sync D3 91 A6 5C; header 01 0A; UTF-8 payload wookiemeat; CRC B1 42; three transmitted frames, two matching frames required. The audible thresholds and default profile/configuration controls remain unchanged.

D05 WAV was regenerated with the unchanged generator and is byte-identical to D03/D04 stimulus: SHA256 6f4d14899f12da6931283e7b1f3ffd24d48bdf7e5b299751d4eaac6216956caf.

    dart run tool/generate_beacon.dart --audible --output=../Acoustic-Beacon-D05-audible.wav
    flutter test --no-pub --dart-define=BEACON_TEST_WAV=../Acoustic-Beacon-D05-audible.wav

Use the same audible configuration on the physical device. After playback, the retained diagnostic trace can distinguish frequency-separated segments from quiet-separated ones. Physical acceptance is pending.