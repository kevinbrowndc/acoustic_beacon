# Verification record — 2026-09-22

## Passed

- Flutter static analysis: **No issues found**.
- Automated suite: **20 tests passed**.
- Synthetic PCM validation: wookiemeat round trip with arbitrary chunk boundaries and sample offsets, repeated frame requirement, corruption rejection, bad CRC rejection, low signal rejection, deterministic random-noise rejection, incomplete-frame rejection, continuous-tone rejection, additive-noise success, configuration bounds, and independent CRC known vector.
- Application integration: synthetic PCM through the capture interface → real DSP → CRC/repeat validation → local content lookup; permission-denied recovery.
- Consumer widgets: onboarding before permission, listening-off state without fabricated content, location/detection distinction, navigation at 200% text scale in dark mode.
- Visual/integration tests in light and dark: microphone-independent test capture through real decoder → Beacon Detected → Save → persisted item; listening and validated-content renders; four primary screen renders.
- Twelve screen images inspected for readable hierarchy, purple theme consistency, spacing, legibility and uncluttered states. Actual native font rendering may differ.
- Two reproducibly generated 48 kHz mono PCM16 test WAVs available (audible 4/5 kHz, ultrasonic 20/21 kHz).

Synthetic capture in automated tests is explicitly a test harness. The installed app's default capture implementation is the phone microphone. No simulation switch exists in the consumer or debug UI.

## Not verified / blocked

- **Physical first milestone remains unverified.** No Android/iPhone was attached. Speaker response, microphone response, sample-rate conversion, distance, false-positive rate and noisy-room robustness require physical trials.
- Android debug compilation is now verified: BUILD SUCCESSFUL using JDK 21 and the checked-in Windows build script. Actual installation and launch still require a phone.
- The build script selects JDK 21 without changing global Flutter settings. A dedicated Java socket directory resolves the local-socket issue; NDK 27.0.12077973 installed using the existing accepted license. No further SDK license was needed for this build.
- iOS native compilation/signing cannot run on this Windows host; use the Mac/Xcode procedure in README.
- VoiceOver/TalkBack, actual microphone interruptions, haptics, permissions, reduced motion on physical OS, long listening battery/CPU use, and saved persistence across physical process termination need device acceptance tests.
- Nearby directory/map, real network backend, redemption, branded launcher artwork and background operation remain future work. Near You explicitly distinguishes location from sound and has no fabricated registered places.

A signed debug APK is delivered. Physical acoustic detection and iOS build success are not claimed.


## Final Android artifact

- Final rebuild: **BUILD SUCCESSFUL**, 1m 42s, using `tool/build_android.ps1`.
- Delivered APK: `Acoustic-Beacon-debug.apk`, 160,984,112 bytes.
- SHA256: `95e9dfdab8facd78c111e7a116071fa426ea43777b443c3e547839a6de92bab6`.
- Signature: apksigner exit 0; v1 and v2 verified; one Android Debug signer.
- Certificate SHA256: `b0dc09c1a7e98c06f6c2a232bfe6060d3d0ac532c9a11b02033fa0d48053400f`.
- App: `com.acousticbeacon.acoustic_beacon`, version 1.0.0 (1), min API 23, target API 35.
- Architectures verified from both APK manifest badging and actual libflutter.so entries: `armeabi-v7a`, `arm64-v8a`, `x86_64`. No incomplete x86 directory is packaged.
- All 20 tests reran successfully and static analysis reported no issues during this build-fix session.
- `git diff --exit-code 8278dce -- lib test tool/generate_beacon.dart pubspec.yaml pubspec.lock beacon-audible.wav beacon-ultrasonic.wav` passed: protocol, application functionality, dependencies and test audio are unchanged.
- Remaining nonfatal build warnings concern third-party Kotlin metadata and deprecated Java/Gradle features. The first full compilation completed despite these warnings; the final rebuilt artifact also completed successfully. Physical phone runtime acceptance is still required.
