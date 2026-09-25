# D03 WAV and Android decoder audit

## Finding and limits

The saved audible WAV is NOT malformed or incompatible with D02. Before any D03 decoding change, the exact file passed the production MicrophoneCapture PCM conversion and BeaconDetector at sample offsets 0, 71 and 239, with odd 1993-byte input chunks. Each run found three preambles, three CRC-valid frames, payload wookiemeat and one two-frame-validated event. Generator output was byte-identical to the saved WAV.

The reproducible defect is the receiver's upper burst-duration limit. D02 accepted only 20–60 ms of above-threshold tone for an 80 ms symbol, although it separately required only 10 ms of silence to delimit symbols. A controlled acoustic-path model (direct WAV plus a 25 ms delayed copy at gain 0.35) extends 40 ms tones to about 65 ms, leaving 15 ms before the next symbol. D02 rejected all 432 bursts, yielding zero preambles and zero valid frames. No transmitted bit or frequency was changed in this reproduction.

D03 derives the maximum accepted burst from symbol duration minus the existing two quiet hops: 80 − 10 = 70 ms. The minimum remains 20 ms. It still requires two noncandidate hops to end a burst. Longer bursts still reset framing; short-burst handling from D02 is retained. This is a receiver tolerance correction, not a new modulation or protocol.

This proves one receiver weakness and its correction. It does NOT prove the Moto G14 recording contains a 25 ms echo. No captured phone PCM was supplied and adb reported no devices. Physical decoding remains unverified; merged bursts that eliminate the required quiet gap can still fail. No claim is made that synthetic echo fully models the user's room or microphone processing.

## Exact format and mapping

| Property | WAV and receiver contract |
| --- | --- |
| Container | RIFF/WAVE, PCM format 1 |
| PCM | 48000 Hz, one channel, signed 16-bit little-endian |
| Sample scale | WAV uses 32767; microphone normalizes by 32768 (expected quantization difference, tested) |
| Bit mapping | 0 = 4000 Hz, 1 = 5000 Hz in audible configuration |
| Bit order | Most significant bit first within every byte |
| Symbol | 3840 samples = 80 ms |
| Tone/gap | 1920 samples tone (40 ms), 1920 zero samples (40 ms) |
| Envelope | 96-sample / 2 ms ramps |
| Synchronization | D3 91 A6 5C, exact 32-bit match |
| Header | Version 01, payload byte count 0A |
| Payload | UTF-8 wookiemeat, 10 bytes |
| Checksum | CRC16/CCITT-FALSE, polynomial 1021, initial FFFF, no reflection/final XOR; covers version, length and payload |
| CRC bytes | B1 42, high byte first |
| Complete frame | D3 91 A6 5C 01 0A 77 6F 6F 6B 69 65 6D 65 61 74 B1 42 |
| Repeats | WAV sends 3; receiver requires 2 matching valid frames |
| Frame/gap | 144 symbols = 11.52 s; 0.5 s silence before each frame and after final frame |
| Total file audio | 36.56 s / 1,754,880 samples / 3,509,760 PCM bytes |
| Detector analysis | 240 samples / 5 ms per block, no dependence on callback arrival time |
| Signal gates | amplitude 0.008, confidence 0.75; unchanged |
| Idle reset | more than 160 ms without a candidate tone |
| Repeated-frame window | 14.52 s for this payload; start-to-start WAV spacing is 12.02 s |

A separate test projects the actual PCM onto 4000 and 5000 Hz, reconstructs all 432 bits, verifies all silent halves and checks independently computed CRC bytes. It does not call the generator's codec to obtain expected frame bytes.

## Android path

Installed record_android 1.5.2 PCMReader configures AudioRecord from the requested sample rate, mono channel mask and PCM16 format. MicrophoneCapture requests 48 kHz/mono/PCM16 with AGC, echo cancellation and noise suppression disabled, carries odd bytes between callbacks, and divides signed little-endian int16 samples by 32768. The regression mocks only the recorder platform's byte source; the production AudioRecorder wrapper, MicrophoneCapture conversion and BeaconDetector all run unchanged.

The debug UI's audible button fills 4000/5000 only; Apply configuration actually changes the controller configuration. Start listening creates the detector from that configuration. The app's default ultrasonic profile was not changed. For this WAV, the active configuration must be 4000/5000 Hz, symbol 80 ms, threshold 0.008 and default confidence 0.75. Preamble NOT FOUND is instantaneous state and returns after a frame; the cumulative Preambles found total is the durable evidence.

## Validation and scope

- D02 baseline exact-WAV test: passed before the receiver change (D03-wav-baseline.log).
- D02 echo regression: failed with preambles=0, frames=0, long=432 (D03-echo-before.log).
- D03 exact and echoed WAV: preambles=3, frames=3, CRC PASS, payload wookiemeat, one validated event, at all three sample offsets.
- Echoed WAV with payload bit changed but original CRC: preambles=3, valid frames=0, CRC failures=3, zero validated events.
- One echoed frame: CRC PASS, one valid frame, zero validated events.
- Full suite: 29 tests passed using the named delivery WAV via BEACON_TEST_WAV.
- Static analysis: no issues.
- No protocol, WAV generator, audio capture, dependency, content or navigation change. Related diagnostic label D03 and versionCode 3 identify this build.

Reproduce in the project directory:

    dart run tool/generate_beacon.dart --audible --output=../Acoustic-Beacon-D03-audible.wav
    flutter test --no-pub --dart-define=BEACON_TEST_WAV=../Acoustic-Beacon-D03-audible.wav

The D03 WAV is deliberately byte-identical to the previous audible WAV, because the transmitter protocol and settings are unchanged. SHA256: 6f4d14899f12da6931283e7b1f3ffd24d48bdf7e5b299751d4eaac6216956caf.
## Delivered artifact verification

JDK 21 debug build succeeded in 1m 28s. APK: ../Acoustic-Beacon-D03.apk.
SHA256: aad9ca3f394689601be1e3705f797d6f291023837b6c95c4964063f79b2c0312.
App package com.acousticbeacon.acoustic_beacon, version 1.0.0 (3), min API 23, target API 35.
Signature verification passed (v1 and v2); signer SHA256 b0dc09c1a7e98c06f6c2a232bfe6060d3d0ac532c9a11b02033fa0d48053400f, same debug signer as D02.
Manifest and actual libflutter.so entries confirm armeabi-v7a, arm64-v8a, x86_64.
Matching test WAV: ../Acoustic-Beacon-D03-audible.wav. Hash and exact-file replay verified above. Hash sidecars accompany both files.
