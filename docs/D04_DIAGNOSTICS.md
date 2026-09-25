# D04 diagnostic build

D03 failed physical Android testing with its matching audible WAV. D04 makes no attempt to fix decoding. Its purpose is to expose the actual phone-side symbol decisions after a single playback.

## Unchanged decisions

D03's detection path remains: 240-sample/5 ms analysis, configured 4000/5000 Hz audible mapping, amplitude 0.008 and confidence 0.75, 80 ms symbol configuration, 20–70 ms accepted tone occupancy, two quiet hops to close a burst, short bursts ignored and long bursts resetting framing. Sync, MSB ordering, payload, CRC and matching repeats are unchanged. No audio capture or generator change. The existing default profile and configuration controls are unchanged; keep the audible configuration already used for D03. The D03 audible WAV is reused byte for byte.

## New observational fields

Each completed burst records its sample-clock start time, majority bit and corresponding configured frequency, candidate tone duration T, wall-clock span through the last candidate block, preceding noncandidate gap G, zero/one vote counts, frequency-transition count, first 80 candidate-block bits, ACCEPT/SHORT/LONG status, SYNC/DATA phase and rolling preamble before/after processing.

T is what the decoder actually uses: candidate-block count times 5 ms. Span additionally exposes single quiet hops bridged inside a burst. G is the gap BEFORE this burst, measured from the previous candidate block's end. Noncandidate can mean weak amplitude or low frequency confidence, not necessarily acoustic silence. Measurements have 5 ms block resolution. Majority frequencies are configured detector bins, not an independent frequency estimate. Each vote is a candidate 5 ms block; the detailed vote string excludes noncandidate blocks and truncates after 80 votes for memory safety, while counts and span retain totals.

The compact photo summary preserves expected sync bits (D3 91 A6 5C), the last actual rolling comparison, closest complete 32-bit comparison, differing-bit count, burst number for that closest match, meaningful reset counts/reasons, any unfinished burst and the first twelve completed bursts. Full comparisons exclude zero padding before 32 real bits arrive. The existing session totals continue to show overall accepted/short/long counts and preamble/CRC results.

The expandable D04 detailed burst log retains the first 64, latest 128 and up to 64 bursts around the closest match. This is bounded in-memory diagnostic logging, not raw audio recording or a persistent disk export. No storage permission or network transfer is added. Silence does not erase the summary or first/best history. Stop preserves it; Start or Apply creates a fresh detector and clears it. No controls or listening behavior were changed.

## One-playback procedure

1. Keep the same audible configuration used for D03 (4000/5000 Hz, 80 ms, threshold 0.008).
2. Start listening, play the entire D03 audible WAV once from the laptop, then Stop listening.
3. Photograph D04 PHOTO SUMMARY at the top of Beacon Debug. If it spans the screen, take overlapping photos without replaying.
4. The expandable D04 detailed burst log contains the closest-match context and first/latest sequences for follow-up photos from the same session. Do not restart listening or Apply before photographing.

## Validation

All 33 tests passed after initial instrumentation. The four focused diagnostic tests passed again after adding retained closest-match context. Static analysis is clean. Tests verify exact tone/gap measurements, full rolling preamble state, 432 bursts for the unchanged WAV, capped history, retention after silence, mixed-frequency votes, short/long rejections, pending long bursts and a 360-pixel-wide Debug screen without layout errors. Existing exact-WAV, CRC rejection, repeat validation, noise and D03 echo tests remain passing.

This build intentionally does not claim physical decoding success or identify the physical failure's cause.
## Verified artifact
JDK 21 build succeeded in 1m 6s. Delivery: Acoustic-Beacon-D04-diagnostic.apk, versionCode 4. APK signature v1/v2 verified; same Android Debug signer as D03. Manifest and packaged Flutter libraries confirm arm64-v8a, armeabi-v7a and x86_64. SHA256: c4fcae12bed70ccc61b1194f0fda0afcdc3d495ee2b49fd54e332e3a311dbc01. Existing D03 audible WAV remains the matching stimulus.

