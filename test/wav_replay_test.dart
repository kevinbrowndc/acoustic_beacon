import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:acoustic_beacon/audio/microphone.dart';
import 'package:acoustic_beacon/dsp/detector.dart';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';
import '../tool/generate_beacon.dart' as generator;

const audible = BeaconConfig(zeroHz: 4000, oneHz: 5000);
const wavPath = String.fromEnvironment(
  'BEACON_TEST_WAV',
  defaultValue: 'beacon-audible.wav',
);

Uint8List readPcm() {
  final bytes = File(wavPath).readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
  expect(data.getUint32(4, Endian.little), bytes.length - 8);
  var offset = 12;
  Uint8List? pcm;
  var foundFormat = false;
  while (offset + 8 <= bytes.length) {
    final tag = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = data.getUint32(offset + 4, Endian.little);
    final start = offset + 8;
    expect(start + size, lessThanOrEqualTo(bytes.length));
    if (tag == 'fmt ') {
      expect(data.getUint16(start, Endian.little), 1);
      expect(data.getUint16(start + 2, Endian.little), 1);
      expect(data.getUint32(start + 4, Endian.little), 48000);
      expect(data.getUint32(start + 8, Endian.little), 96000);
      expect(data.getUint16(start + 12, Endian.little), 2);
      expect(data.getUint16(start + 14, Endian.little), 16);
      foundFormat = true;
    } else if (tag == 'data') {
      pcm = Uint8List.sublistView(bytes, start, start + size);
    }
    offset = start + size + (size & 1);
  }
  expect(foundFormat, isTrue);
  expect(pcm, isNotNull);
  expect(pcm!.length, 3509760); // 36.56 seconds, three 18-byte frames.
  return pcm;
}

class WavRecordPlatform extends RecordPlatform {
  final chunks = StreamController<Uint8List>();
  @override
  Future<void> create(String id) async {}
  @override
  Future<bool> hasPermission(String id, {bool request = true}) async => true;
  @override
  Stream<RecordState> onStateChanged(String id) => const Stream.empty();
  @override
  Future<Stream<Uint8List>> startStream(String id, RecordConfig config) async {
    expect(config.encoder, AudioEncoder.pcm16bits);
    expect(config.sampleRate, 48000);
    expect(config.numChannels, 1);
    expect(config.autoGain, isFalse);
    expect(config.echoCancel, isFalse);
    expect(config.noiseSuppress, isFalse);
    return chunks.stream;
  }

  @override
  Future<String?> stop(String id) async => null;
  @override
  Future<void> dispose(String id) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<SignalDiagnostics> replay(
  Uint8List pcm, {
  int offset = 0,
  int expectedFrames = 3,
  int expectedPreambles = 3,
  int expectedCrcFailures = 0,
}) async {
  final savedPlatform = RecordPlatform.instance;
  final platform = WavRecordPlatform();
  RecordPlatform.instance = platform;
  final microphone = MicrophoneCapture();
  final received = <String>[];
  final detector = BeaconDetector(audible, (p, _) => received.add(p));
  final stream = await microphone.start();
  final done = Completer<void>();
  var count = 0;
  final input = Uint8List.fromList([...List.filled(offset * 2, 0), ...pcm]);
  final subscription = stream.listen((samples) {
    detector.add(samples);
    count += samples.length;
    if (count == input.length ~/ 2) done.complete();
  });
  try {
    // Odd byte chunks exercise the production carry-byte logic as well.
    for (var i = 0; i < input.length; i += 1993) {
      platform.chunks.add(
        Uint8List.sublistView(input, i, min(i + 1993, input.length)),
      );
    }
    await done.future.timeout(const Duration(seconds: 30));
    final d = detector.diagnostics;
    // ignore: avoid_print
    print(
      'WAV replay offset=$offset: preambles=${d.preamblesFound}, frames=${d.acceptedFrames}, CRC=${d.checksum}, payload=${d.payload}, events=${d.validatedBeacons}, short=${d.shortBursts}, long=${d.longBursts}',
    );
    expect(d.preamblesFound, expectedPreambles);
    expect(d.acceptedFrames, expectedFrames);
    expect(d.crcFailures, expectedCrcFailures);
    expect(d.checksum, expectedCrcFailures > 0 ? 'FAIL' : 'PASS');
    expect(d.payload, expectedFrames > 0 ? 'wookiemeat' : '');
    expect(d.validatedBeacons, expectedFrames ~/ 2);
    expect(received, expectedFrames >= 2 ? ['wookiemeat'] : <String>[]);
    return d;
  } finally {
    await subscription.cancel();
    await microphone.stop();
    await microphone.dispose();
    await platform.chunks.close();
    RecordPlatform.instance = savedPlatform;
  }
}

Uint8List withEcho(Uint8List pcm) {
  final original = ByteData.sublistView(pcm);
  final echoed = Uint8List(pcm.length);
  final data = ByteData.sublistView(echoed);
  const delaySamples = 1200;
  for (var i = 0; i < pcm.length ~/ 2; i++) {
    final direct = original.getInt16(i * 2, Endian.little);
    final reflection = i >= delaySamples
        ? .35 * original.getInt16((i - delaySamples) * 2, Endian.little)
        : 0.0;
    data.setInt16(
      i * 2,
      (direct + reflection).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  return echoed;
}

void main() {
  test('echo tolerance does not bypass CRC on altered payload bits', () async {
    final pcm = Uint8List.fromList(readPcm());
    final data = ByteData.sublistView(pcm);
    for (var repeat = 0; repeat < 3; repeat++) {
      // Flip the first payload bit (w: MSB=0) to one without updating CRC.
      final start = 24000 + repeat * (24000 + 144 * 3840) + 6 * 8 * 3840;
      for (var i = 0; i < 1920; i++) {
        final ramp = min(1.0, min(i / 96, (1920 - i) / 96));
        final sample = .6 * ramp * sin(2 * pi * 5000 * i / 48000);
        data.setInt16((start + i) * 2, (sample * 32767).round(), Endian.little);
      }
    }
    await replay(withEcho(pcm), expectedFrames: 0, expectedCrcFailures: 3);
  });

  test('single echoed frame still cannot validate a beacon', () async {
    final pcm = Uint8List.fromList(readPcm());
    pcm.fillRange(2 * (24000 + 144 * 3840), pcm.length, 0);
    await replay(withEcho(pcm), expectedFrames: 1, expectedPreambles: 1);
  });

  test('same WAV with a 25 ms echo retains synchronization and CRC', () async {
    final pcm = readPcm();
    // Same transmitted symbols plus a quieter delayed acoustic reflection.
    final echoed = withEcho(pcm);
    for (final offset in [0, 71, 239]) {
      await replay(echoed, offset: offset);
    }
  });

  test('saved WAV is byte-identical to explicit audible generator output', () {
    final temp = Directory.systemTemp.createTempSync('beacon-wav-test-');
    try {
      final path = '${temp.path}/generated.wav';
      generator.main(['--audible', '--output=$path']);
      expect(File(path).readAsBytesSync(), File(wavPath).readAsBytesSync());
      readPcm();
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test(
    'exact saved WAV passes production PCM conversion and decoder',
    () async {
      final pcm = readPcm();
      for (final offset in [0, 71, 239]) {
        await replay(pcm, offset: offset);
      }
    },
  );

  test(
    'independent waveform audit verifies all frame bits and silent halves',
    () {
      final pcm = ByteData.sublistView(readPcm());
      final expected = [
        0xd3,
        0x91,
        0xa6,
        0x5c,
        1,
        10,
        ...'wookiemeat'.codeUnits,
      ];
      var crc = 0xffff;
      for (final byte in expected.skip(4)) {
        for (var bit = 7; bit >= 0; bit--) {
          final feedback = ((crc >> 15) ^ (byte >> bit)) & 1;
          crc = ((crc << 1) & 0xffff) ^ (feedback == 1 ? 0x1021 : 0);
        }
      }
      expected.addAll([crc >> 8, crc & 255]);
      // ignore: avoid_print
      print(
        'Independent frame bytes: ${expected.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
      );
      double energy(int start, int hz) {
        var real = 0.0, imaginary = 0.0;
        for (var i = 480; i < 1440; i++) {
          final value = pcm.getInt16((start + i) * 2, Endian.little) / 32768;
          real += value * cos(2 * pi * hz * i / 48000);
          imaginary += value * sin(2 * pi * hz * i / 48000);
        }
        return real * real + imaginary * imaginary;
      }

      for (var repeat = 0; repeat < 3; repeat++) {
        final start = 24000 + repeat * (24000 + 144 * 3840);
        final decoded = <int>[];
        for (var byte = 0; byte < 18; byte++) {
          var value = 0;
          for (var bit = 0; bit < 8; bit++) {
            final symbolStart = start + (byte * 8 + bit) * 3840;
            final zero = energy(symbolStart, 4000),
                one = energy(symbolStart, 5000);
            expect(max(zero, one), greaterThan(10000));
            expect(min(zero, one), lessThan(1));
            value = (value << 1) | (one > zero ? 1 : 0);
            for (var sample = 1920; sample < 3840; sample++) {
              expect(
                pcm.getInt16((symbolStart + sample) * 2, Endian.little),
                0,
              );
            }
          }
          decoded.add(value);
        }
        expect(decoded, expected);
      }
    },
  );
}
