# D02 receiver correction — 2026-09-24

D01 physical reports: accepted symbols 370; short bursts 140; long bursts 220; preambles 0; CRC-valid frames 0. Recent burst durations reported: 45, 5, 60, 45, 45 ms. Candidate blocks 19708, noncandidate blocks 268884, peak tone amplitude 0.44181. These are cumulative user-reported readings, not a controlled recording. They do not establish the cause of the long bursts.

A reproducible receiver defect was isolated: a 5 ms above-threshold tone in the silent half of a symbol reset all accumulated synchronization/frame bits. The new regression inserts this interference between every symbol of two otherwise valid audible frames, checks offsets 0, 71 and 239 samples and 997-sample delivery chunks. It failed before the fix (no payload) and passes afterward (two CRC-valid frames and one validated payload).

D02 ignores subminimum-duration bursts rather than clearing frame progress. Long bursts still reset the frame; idle timeout, sync word, header validation, CRC and repeated-frame requirement remain intact. No transmitter, codec, frequencies, waveform or default thresholds were changed. The visible diagnostic label is D02 and the existing pending version increment to 1.0.0+2 is retained.

Validation: all 23 Flutter tests passed; Flutter analysis reported no issues. Physical acoustic decoding is not yet verified. This correction addresses brief interference; it does not claim to resolve every source of long or merged bursts.
## Verified Android artifact

Build succeeded with JDK 21 in 3m 5s. Delivered file: ../Acoustic-Beacon-D02.apk (160985566 bytes).
SHA256: 8d25edd9292a851bdd3a65a1600abaa8588193efa9fa97167f02de15ad3932d0.
Package com.acousticbeacon.acoustic_beacon; versionName 1.0.0; versionCode 2; min API 23; target API 35.
Signature verification exited 0; v1 and v2 verified. Same Android Debug signer as D01: b0dc09c1a7e98c06f6c2a232bfe6060d3d0ac532c9a11b02033fa0d48053400f.
Both manifest badging and packaged libflutter.so entries confirm arm64-v8a, armeabi-v7a and x86_64.
Build produced nonfatal SDK XML/deprecation warnings. apksigner also reported v1 META-INF coverage warnings; v2 verification passed.
The delivery copy hash matches the build output. Protocol, generator, WAV files and dependency lockfile have no Git diff.
