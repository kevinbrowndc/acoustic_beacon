# Acoustic Beacon

One Flutter codebase for Android and iOS. Real foreground microphone PCM feeds a local, configurable acoustic decoder. Only repeated CRC-valid frames can create a Detected card. Nothing detected opens a URL, launches another app, downloads, or purchases anything.

## Status

Implemented: real microphone stream adapter; Goertzel tone detection; experimental burst-FSK encoder/decoder; synchronization, CRC, confidence and repeated-frame validation; WAV generator; local content repository; onboarding; four consumer destinations; saved content persistence; light/dark appearance; separate permission requests; hidden diagnostics; foreground lifecycle handling.

Not yet physically verified: speaker → microphone → decoded `wookiemeat` on Android or iPhone. Synthetic tests exercise the same DSP and codec, but cannot establish device frequency response or real-world reliability.

Near You uses actual location permission and coordinates, with an empty replaceable location repository. There is no live merchant directory or map renderer yet. Get Deal opens an in-app explanation for the test content; there is no redemption backend. Push notifications and background listening are not implemented. Launcher icons remain Flutter template assets. Consumer UI is a styled prototype, not a production release.

## Requirements and run

- Tested Dart/Flutter environment: Flutter 3.32.0, Dart 3.8.0. Dependencies are locked in `pubspec.lock` to compatible versions.
- Android: SDK with platform 35, build tools, NDK 27.0.12077973, Android SDK licenses accepted, and a compatible Java runtime (JDK 17 or 21 for the checked-in Gradle 8.12 setup). App minimum Android API 23.
- iOS: macOS, Xcode, CocoaPods, iOS 13+, and a signing team for a physical phone. Windows cannot compile or sign the iPhone app.

From this folder:

```sh
flutter pub get
flutter analyze
flutter test
flutter devices
flutter run -d DEVICE_ID
```

Android: enable Developer options and USB debugging, connect and authorize the phone, then run the above. Review and accept required Android SDK licenses yourself with `flutter doctor --android-licenses`. Build a debug installer with `flutter build apk --debug`; install using `flutter install -d DEVICE_ID` after a successful build.

iPhone: copy this entire project to your Mac, run `flutter pub get`, run `pod install` inside `ios`, open `ios/Runner.xcworkspace` in Xcode, choose your signing team and a unique bundle ID if needed, connect/trust the phone and enable Developer Mode, then run from Xcode or `flutter run -d DEVICE_ID`. Choose microphone access when prompted. Do not enable background audio modes.

The checked-in Android release configuration uses a development signing key. Configure distribution signing before any release.

### Environment verification on 2026-09-22

Android debug compilation now succeeds with verified Temurin JDK 21 and a dedicated Java socket directory. The final APK passes Android signature verification (v1/v2), supports armeabi-v7a, arm64-v8a and x86_64, and requires Android API 23 or later. All 20 automated tests passed again; static analysis found no issues. See `docs/ANDROID_BUILD.md` for the repeatable Windows build script and `docs/android-apk-verification.json` for the delivered file checksum. No physical mobile device was attached; acoustic acceptance and iOS compilation remain unverified.

## Generate and play the beacon

Two generated WAVs are included:

- `beacon-ultrasonic.wav`: 20,000 / 21,000 Hz; default app configuration.
- `beacon-audible.wav`: 4,000 / 5,000 Hz; audible control for separating protocol problems from high-frequency hardware limitations.

```sh
dart run tool/generate_beacon.dart
dart run tool/generate_beacon.dart --audible
```

Each WAV is 48 kHz mono PCM16, about 36.6 seconds, with three transmissions of `wookiemeat`. Two matching valid transmissions are required, so expect a result approximately 24 seconds after playback begins if the first two frames are received intact. Start listening before playback. Play the original WAV at normal speed; avoid lossy transcoding, EQ, spatial enhancement, and streaming services that filter high frequencies.

## First physical test

1. Install/run the app on a real Android phone or iPhone using the platform steps above.
2. Complete onboarding, enable microphone access, and keep the app foregrounded with the screen awake.
3. For a reliable audible control first, open Settings and **long-press About Acoustic Beacon**. Tap **Fill audible control frequencies**, **Apply configuration**, then **Start listening**. This changes the actual microphone decoder; it does not simulate detection.
4. Place the phone 0.5 m from a laptop speaker. Play `beacon-audible.wav` at a comfortable, moderate volume. Let the full file play. Expect payload `wookiemeat`, CRC PASS, at least two CRC-valid frames, then a Beacon Detected card on Detected. Tone/candidate activity alone is not success.
5. Return to debug, enter **20000** and **21000**, Apply configuration, then Start listening. Play `beacon-ultrasonic.wav` from the same source. The default threshold is **0.008**, symbol duration **80 ms**. Do not increase volume aggressively just because high frequencies are inaudible.
6. Try Save and confirm the item remains after an app restart. Get Deal must show only the in-app test explanation. Near You must never show acoustic detection merely from GPS.
7. Background the app or lock the phone: listening should stop. Return and deliberately restart listening. Test denied microphone permission and recovery through Settings → Microphone.
8. Send back phone model/OS, speaker/source, frequency pair, distance, volume setting, candidate/preamble/CRC counters, payload, and whether the consumer card appeared. Use the trial sheet in `docs/physical-trials.csv`.

The full laptop/TV/home/PA matrix and failure triage are in `docs/PHYSICAL_TESTING.md`. Stop protocol changes until those results are available.

## Architecture

- `lib/audio/microphone.dart`: `PcmCapture` boundary; `record` supplies little-endian mono PCM16; handles odd byte chunks. Recorder is created only on deliberate listening start.
- `lib/dsp/detector.dart`: pure Dart streaming Goertzel detector. It does not import Flutter or know about merchants/UI.
- `lib/protocol/beacon_protocol.dart`: configuration, replaceable `BeaconCodec`, CRC, encoder, synthesizer, WAV serialization.
- `lib/application/beacon_controller.dart`: lifecycle/state orchestration, repeated valid detection → content lookup, UI notification throttling and duplicate suppression.
- `lib/data/content.dart`: replaceable content and location repository contracts; local development implementations. No network transport or audio upload exists.
- `lib/presentation/app.dart`: branded themes, responsive consumer components, onboarding, bottom navigation and separate diagnostics. Candidate states remain invisible to consumer offer presentation.
- `tool/generate_beacon.dart`: reproducible external-speaker transmission utility.
- `test/`: acoustic negative/positive tests, controller permission/content tests, onboarding/navigation and screenshot regression tests. Fake capture is used only in tests.

Application states: idle, requestingPermission, listening, candidateSignal, decoding, validBeacon, error. Listening is deliberately stopped on background/lock. No automatic restart occurs after returning to the app. Raw audio exists only transiently in memory for analysis; there are no audio files, network uploads, or retained recordings from capture. Saved content and appearance/onboarding preferences persist locally.

## Experimental protocol v1

This is a reversible laboratory protocol, **not a final production specification**. 21 kHz is not assumed universal.

- 48,000 samples/second; mono PCM16.
- Default binary tones 20/21 kHz; audible control 4/5 kHz.
- Each 80 ms symbol has a 40 ms tone burst, then 40 ms silence. A 2 ms ramp reduces clicks.
- Most-significant bit first. Frame: sync `D3 91 A6 5C`, version `01`, UTF-8 byte length (1–64), payload, CRC16-CCITT-FALSE high byte then low byte.
- CRC covers version, length and payload. Initial value FFFF; polynomial 1021; no reflection; xor-out 0000.
- 500 ms interframe gap. Two matching valid frames within a frame-length-derived time window are required. A single frame is diagnostic evidence only.
- Hann-windowed Goertzel analysis in 240-sample (5 ms) blocks measures the two configured bins. Dominant amplitude >= 0.008 and dominance ratio >= 0.75 qualify a tone. Burst duration is bounded; silence segments establish symbols independently of arbitrary capture alignment. A continuous carrier is not a frame.
- Silence longer than two symbol periods drops incomplete framing. Version, length, UTF-8, CRC, and repeated-frame checks all gate acceptance.
- A validated content event is suppressed for 30 seconds when the same content is already displayed. Debug frame counters continue updating.

Tradeoff: tone/silence symbols are slower but simplify synchronization and timing experiments. The small fixed-size DSP runs on the Dart UI isolate, with consumer notifications throttled to about 7 Hz. Profile on devices before deciding whether to move analysis to a worker isolate. Frequencies, threshold and symbol duration can be edited on debug; configuration resets at launch to avoid accidentally carrying experimental settings into later runs. Other parameters are in `BeaconConfig` and must match the generator.

Limitations: no multipath equalization, sample-clock recovery beyond burst segmentation, frequency-offset search, forward error correction, or cryptographic authentication. CRC rejects corruption; it does not establish the transmitter's identity. Replayed valid beacons can be detected, but cannot trigger automatic actions. Production content lookup should add authentication, expiry, abuse controls and explicit action validation independently of DSP.

The record plugin exposes requested output sample rate, not independently measured hardware rate. Debug labels that distinction. Physical tests must verify hardware/OS filtering and capture characteristics; AGC/noise suppression/echo cancellation are requested off but device behavior can vary.

## Dependencies

| Dependency | Use | Locked compatible version |
|---|---|---|
| Flutter/Dart | Android/iOS app and pure Dart DSP | 3.32.0 / 3.8.0 |
| record | Real PCM16 microphone streams and microphone permission | 6.2.1 |
| shared_preferences | Saved content, onboarding, appearance | 2.5.3 |
| geolocator | Contextual location permission, coordinates, OS settings | 14.0.2 |
| flutter_test / flutter_lints | Regression checks and static analysis | SDK / 5.0.0 |

Packages were selected through dependency resolution for the available Flutter SDK, rather than forcing incompatible newer major versions. Review upgrades together with device tests. References: [record](https://pub.dev/packages/record/versions/6.2.1), [shared_preferences](https://pub.dev/packages/shared_preferences/versions/2.5.3), [geolocator](https://pub.dev/packages/geolocator/versions/14.0.2).

## UI and accessibility

Purple seed-based light/dark colors, calm signal rings, 24 px card rounding and content padding, large primary actions, safe areas and capped content width form the prototype design system. Standard text respects OS scaling; lists scroll; icons accompany text rather than carrying state alone. Reduced-motion mode stops the listening pulse. Candidate signal data is restricted to the debug route. Platform permission, TalkBack/VoiceOver, physical haptics, and device-level accessibility still need manual testing.

Screenshots under `test/goldens/` are Flutter test renders using locally available Flutter fonts. Regenerate intentionally with `flutter test --update-goldens`; different Flutter engines/fonts can alter golden pixels. The tests contain no production-only simulated detector.

Custom matching settings can be reproduced without editing source:

```sh
dart run tool/generate_beacon.dart --zero-hz=19000 --one-hz=20000 --symbol-ms=100 --repetitions=3 --amplitude=0.6 --output=custom-beacon.wav
```

Apply the same two frequencies and symbol duration in the debug screen. `--payload=...` selects an alternate UTF-8 payload. `--repetitions=1` produces a negative control that must not trigger content.

