# Production ultrasonic profile - consumer 1.0.6+17

Supersedes the audible-default decision in MERCHANT_D09_FIX.md. Production transmitter and receiver both use 20,000 Hz for 0 and 21,000 Hz for 1, from backend/app/d09_profile.json. The generated consumer lib/protocol/d09_profile.dart is checked by tool/test_merchant_wav.py.

Unchanged: 48 kHz PCM16 mono; 40 ms slots; 20 ms tone and 20 ms quiet; CDA8 preamble; 24-bit network-order ID, MSB-first; CRC-8 polynomial 07/init0/xor0; amplitude .6; 96-sample ramps; three repeats with existing silence; .008 threshold/.75 confidence; exact preamble and CRC gates; provisioning and APIs.

The actual backend WAVs for ABC123 and 96939B are replayed through the unchanged consumer decoder using production defaults. Explicit 4/5 kHz diagnostic decoding rejects these production WAVs. Legacy audible fixture tests explicitly configure the diagnostic profile rather than changing production settings.

The production consumer remains the sibling acoustic_beacon_consumer checkout; its versioned update is exported in docs/consumer-patches/0002-production-ultrasonic.patch. The obsolete root Flutter prototype and pre-existing experimental edits there remain untouched. Apply consumer patches in sequence to the original consumer baseline when reconstructing it.

Physical test: install the 1.0.6+17 APK, open it and start listening. Reload the merchant Beacon page and play a newly fetched/downloaded beacon WAV. Do not reuse saved 4/5 kHz audio. Confirm the decoded ID and corresponding active promotion. No settings change or audible fallback is required or selected. Physical ultrasonic performance still requires this test.
