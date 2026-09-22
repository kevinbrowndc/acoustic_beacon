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
- Android debug build attempted twice, including IPv4 preference. Both failed before compilation with Gradle `java.io.IOException: Unable to establish loopback connection`. Thus native Android compilation and install are not certified by this run.
- Android doctor also reports unaccepted SDK licenses, and the selected Android Studio JDK is 25.0.3. Review licenses and use a compatible JDK 17/21; local Gradle loopback access must work.
- iOS native compilation/signing cannot run on this Windows host; use the Mac/Xcode procedure in README.
- VoiceOver/TalkBack, actual microphone interruptions, haptics, permissions, reduced motion on physical OS, long listening battery/CPU use, and saved persistence across physical process termination need device acceptance tests.
- Nearby directory/map, real network backend, redemption, branded launcher artwork and background operation remain future work. Near You explicitly distinguishes location from sound and has no fabricated registered places.

No physical detection success, APK, or IPA is claimed.
