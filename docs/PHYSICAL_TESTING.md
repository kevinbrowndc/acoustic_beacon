# Physical-device test protocol

Use an actual phone microphone. A simulator/emulator, generated PCM unit test, or GPS match cannot satisfy the physical milestone.

## Keep a controlled baseline

Record phone/OS/app commit, source/speaker model, output path, WAV filename, carrier pair, symbol timing, threshold, distance, orientation, playback volume, background noise, and timestamp. Use original WAV at 1x speed. Disable EQ/enhancement if possible. Start at 0.5 m and a moderate comfortable volume. The audible control uses 4/5 kHz; ultrasonic default uses 20/21 kHz. Avoid excessive high-frequency playback levels.

Run five complete file playbacks per configuration. Stop/restart listening between independent trials to reset counters; note that an earlier content card may remain visibly timestamped. A trial succeeds only if two valid matching frames produce a fresh detection timestamp and payload `wookiemeat`. Count tone/candidate sightings separately from successful decodes. Capture debug screenshots after each trial, without recording raw audio.

## Source matrix

| Source | Playback procedure | Main variables |
|---|---|---|
| Laptop → phone | Play local WAV using built-in speakers, then a wired output if available | OS output rate, speaker model, enhancement settings |
| TV → phone | Play WAV using supported USB media playback or laptop HDMI; verify file is not transcoded | TV processing, soundbar route, PCM support |
| Home speaker → phone | Prefer wired input from laptop; compare Bluetooth as a separate trial | Codec bandwidth/filtering, receiver EQ |
| PA/external → phone | Play local WAV through a line input at moderate gain | Tweeter response, mixer processing, room reflections |

For every source, run audible control first, then ultrasonic. Test distances 0.5, 1, 2 and 5 m only after a successful closer trial. Repeat with phone facing toward/away from speaker; then compare quiet room, speech/music and noisier conditions. Never change frequency, distance, gain and threshold simultaneously.

## Negative controls

- At least 10 minutes of quiet, ordinary speech/music and environmental sounds without encoded beacon playback. Log candidate count qualitatively and valid detections quantitatively. Expected valid events: zero. Report false positives as events/hour and total observation time; ten minutes cannot establish a production false-positive rate.
- A lone continuous tone must not create a card.
- A single valid frame must not create a card (generate using synthesize repetitions: 1).
- Stop a WAV halfway through the first frame: it must not create a card.
- Deny microphone permission: the UI must explain the issue and offer recovery.
- Use Near You with location allowed and microphone off: no Detected card may be created.
- Background/lock: capture stops; return requires explicit restart. Test interruptions such as calls or another app taking microphone ownership.

## Interpreting failures

No candidate energy: verify listening active, matching WAV/config, output device and volume. If audible control works but ultrasonic fails, suspect hardware bandwidth/filtering first.

Candidate but no preamble: verify frequency pair/symbol duration; note clipping, missed gaps or room echoes. Do not call this decoding.

Preamble then CRC FAIL: record distance, signal level and noise; retry a controlled baseline. Do not loosen validation merely to display an offer.

CRC PASS but no card: ensure two matching frames arrived within the repeat window. Check accepted-frame count, last detection timestamp and duplicate suppression. Unknown valid payloads show a validated-beacon message without a fabricated merchant.

## UI review on devices

Review onboarding, off/permission/error states, listening, validated content, empty/populated Saved, Near You permission states, Settings and debug. Check both themes, largest text setting, TalkBack/VoiceOver, 48 px controls, safe areas, reduced motion, navigation back behavior, saved persistence, and no automatic external action. Test Get Deal and Save only after a microphone-backed detection for acceptance testing.

## Report back

Send completed physical-trials.csv plus debug screenshots and the source/phone details. State separately: tone heard by detector, preamble found, CRC-valid frame count, repeated validated event, consumer card shown. Protocol tuning should follow these observations, not precede them.
