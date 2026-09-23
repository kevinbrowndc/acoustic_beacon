import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:acoustic_beacon/dsp/detector.dart';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';

void main() {
  const config = BeaconConfig();
  final codec = ExperimentalCodec();
  test(
    'diagnostics retain symbol and preamble totals without weakening validation',
    () {
      final received = <String>[];
      final detector = BeaconDetector(
        config,
        (payload, _) => received.add(payload),
      );
      detector.add(
        synthesize(config, codec.encode('wookiemeat'), repetitions: 2),
      );
      final d = detector.diagnostics;
      expect(received, ['wookiemeat']);
      expect(d.acceptedSymbols, 288);
      expect(d.preamblesFound, 2);
      expect(d.acceptedFrames, 2);
      expect(d.validatedBeacons, 1);
      expect(d.matchingFrames, 2);
      expect(d.shortBursts, 0);
      expect(d.longBursts, 0);
      expect(d.quietBlocks, greaterThan(0));
      expect(d.recentBurstMs.length, 20);
      expect(d.preamble, isFalse);
    },
  );
  test('diagnostics expose rejected durations and never invent a beacon', () {
    final detector = BeaconDetector(
      config,
      (_, _) => fail('Invalid burst decoded'),
    );
    List<double> tone(int ms) =>
        List.generate(48 * ms, (i) => .5 * sin(2 * pi * 20000 * i / 48000));
    detector.add([
      ...tone(10),
      ...List.filled(4800, 0.0),
      ...tone(100),
      ...List.filled(4800, 0.0),
    ]);
    expect(detector.diagnostics.shortBursts, 1);
    expect(detector.diagnostics.longBursts, 1);
    expect(detector.diagnostics.acceptedSymbols, 0);
    expect(detector.diagnostics.preamblesFound, 0);
  });
  List<String> detect(List<double> samples, {int offset = 0}) {
    final received = <String>[];
    final detector = BeaconDetector(
      config,
      (payload, _) => received.add(payload),
    );
    final input = [...List.filled(offset, 0.0), ...samples];
    for (var i = 0; i < input.length; i += 997) {
      detector.add(input.sublist(i, min(i + 997, input.length)));
    }
    return received;
  }

  test('CRC16 CCITT-FALSE known vector', () {
    expect(ExperimentalCodec.crc('123456789'.codeUnits), 0x29b1);
  });
  test('codec round trip and payload bound', () {
    final frame = codec.encode('wookiemeat');
    expect(codec.decode(frame.sublist(4)), 'wookiemeat');
    expect(() => codec.encode('x' * 65), throwsArgumentError);
  });
  test('valid PCM beacon across arbitrary chunks and sample alignment', () {
    for (final offset in [0, 71, 239]) {
      expect(
        detect(
          synthesize(config, codec.encode('wookiemeat'), repetitions: 2),
          offset: offset,
        ),
        ['wookiemeat'],
      );
    }
  });
  test('single valid frame never triggers content', () {
    expect(
      detect(synthesize(config, codec.encode('wookiemeat'), repetitions: 1)),
      isEmpty,
    );
  });
  test('corrupted payload rejected', () {
    final frame = codec.encode('wookiemeat');
    frame[7] ^= 4;
    expect(detect(synthesize(config, frame)), isEmpty);
  });
  test('incorrect checksum rejected', () {
    final frame = codec.encode('wookiemeat');
    frame[frame.length - 1] ^= 1;
    expect(detect(synthesize(config, frame)), isEmpty);
  });
  test('insufficient signal rejected', () {
    expect(
      detect(synthesize(config, codec.encode('wookiemeat'), amplitude: .001)),
      isEmpty,
    );
  });
  test('random noise rejected', () {
    final random = Random(42);
    expect(
      detect(List.generate(48000 * 10, (_) => (random.nextDouble() - .5) * .3)),
      isEmpty,
    );
  });
  test('incomplete transmission rejected', () {
    final samples = synthesize(
      config,
      codec.encode('wookiemeat'),
      repetitions: 1,
    );
    expect(detect(samples.sublist(0, samples.length ~/ 2)), isEmpty);
  });
  test('continuous carrier is tone only', () {
    expect(
      detect(
        List.generate(48000 * 3, (i) => .5 * sin(2 * pi * 21000 * i / 48000)),
      ),
      isEmpty,
    );
  });
  test('additive noise still allows repeated frame validation', () {
    final random = Random(8);
    final samples = synthesize(
      config,
      codec.encode('wookiemeat'),
      repetitions: 2,
    );
    expect(
      detect(
        samples.map((e) => e + (random.nextDouble() - .5) * .003).toList(),
      ),
      ['wookiemeat'],
    );
  });
  test('invalid configuration rejected', () {
    expect(
      () => const BeaconConfig(oneHz: 24000).validate(),
      throwsArgumentError,
    );
  });
}
