# Moto G14 audible trials — 2026-09-23

User-reported physical observations. Exact trial times, Android version, laptop model, volume percentage and room conditions were not provided. Original audible WAV reportedly played through laptop built-in speakers; short high-pitched beeps were audible. No raw microphone audio was requested or retained.

| Trial group | Distance | Threshold | Observations |
|---|---|---|---|
| Initial setup / repeated playback | Later clarified as about 20 cm, not the planned 50 cm | 0.003 discovered on screen | 4000/5000 Hz, 80 ms. Candidate YES, reported confidence 99.7%, no preamble observed, no decoded payload. Not the specified baseline threshold. |
| Corrected baseline / repeated playback | About 20 cm | 0.008 | Microphone ACTIVE. Strongest configured frequency switches 4000/5000. Candidate reportedly always YES during playback; no preamble observed; payload empty, CRC Waiting, valid frames 0, last validated detection None. One playback amplitude reading 0.00836. |
| Silence observation | About 20 cm | 0.008 | Candidate NO after playback stopped. User later clarified amplitude 0.04349 and confidence fluctuating 60–70%. These were sequential manual observations, not a simultaneous captured sample. |
| Controlled closer-distance test | About 5 cm | 0.008 | Volume unchanged. Full playback: valid frames 0, preamble never observed. Subsequent playback peak approximately 0.04. No validated event reported. |

The user could not increase volume; it is not established that the laptop was at maximum volume. A suggested volume change was not performed. Individual repeat counts are unknown. Stop/playback/listening were confirmed stopped before source inspection.

## Classification and next measurement

Tone reception is supported by frequency switching and candidate reports. Complete capture failure is unlikely, but physical capture quality has not been independently measured. The failure is before a validated frame; available evidence does not distinguish burst/symbol timing (D), preamble synchronization (E), or sporadic tone discrimination (C). Neither CRC failure nor repeat-validation failure is established: CRC remained Waiting.

The live diagnostic screen is throttled to >=150 ms updates, while the symbols last 80 ms with 40 ms bursts. Therefore a visually continuous Candidate YES and no observed transient Preamble FOUND do not reliably establish decoder-internal timing. Display aliasing is an observability limitation, not proven to be the acoustic failure.

D01 adds cumulative measurements only: processed samples, candidate/noncandidate blocks, accepted symbols, short/long burst rejection counts, preamble matches, invalid headers, CRC/payload failures, matching-frame count and validated events. It retains the last 20 burst lengths and peak tone amplitude, with no audio retention. Counters survive Stop listening and reset on Start listening/Apply.

Hypotheses: many rejected durations support a timing/segmentation problem; accepted symbols with no preamble supports a synchronization/reconstruction problem; preamble plus invalid headers/CRC failures localizes failure later. These are tests of hypotheses, not permission to weaken acceptance. Existing thresholds, timing, frequencies, CRC and repeated-frame decisions are unchanged.

D01 should repeat the same 4/5 kHz, threshold 0.008, 80 ms trial at the last documented 5 cm distance and unchanged volume. Stop listening after playback, then read retained totals without racing live values. Do not proceed to ultrasonic testing yet.

## D01 build verification

- 22 automated tests passed; static analysis: no issues.
- Android build successful under JDK 21; same debug signing certificate as baseline.
- APK: Acoustic-Beacon-D01-diagnostics.apk; SHA256: e7cac951d73fa393c6e308a01aedb64c596d173ff0c548b986df46d95efd9e00
- Original Acoustic-Beacon-debug.apk remains unchanged (SHA256 95e9dfdab8facd78c111e7a116071fa426ea43777b443c3e547839a6de92bab6).
- Same application ID/version, install as an update. Debug screen explicitly says Diagnostic build D01.
- Changes are additive diagnostic counters and debug text only; source diff confirms codec, microphone configuration, state controller, WAV generator, dependency versions and WAV files unchanged. Detection branches still use the original thresholds and validation logic.
- Synthetic ideal two-frame test retains 288 accepted symbols, 2 preambles, 2 valid frames and 1 validated event. Short/long-burst test exposes rejected durations without producing an event. These are instrumentation checks, not proof of physical decoding.
