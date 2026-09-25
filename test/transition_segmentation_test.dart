import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:acoustic_beacon/dsp/detector.dart';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';
import 'wav_replay_test.dart' show readPcm;

const audible = BeaconConfig(zeroHz: 4000, oneHz: 5000);
List<double> tone(int ms, int bit) => List.generate(
  ms * 48,
  (i) => .4 * sin(2 * pi * (bit == 0 ? 4000 : 5000) * i / 48000),
);
BeaconDetector detect(
  List<double> samples, {
  int offset = 0,
  void Function(String, double)? onBeacon,
}) {
  final detector = BeaconDetector(audible, onBeacon ?? (_, _) {});
  final input = [...List.filled(offset, 0.0), ...samples];
  for (var i = 0; i < input.length; i += 997) {
    detector.add(input.sublist(i, min(i + 997, input.length)));
  }
  return detector;
}

List<double> mergedWav({bool corrupt = false, bool single = false}) {
  final data = ByteData.sublistView(readPcm());
  final samples = List.generate(
    data.lengthInBytes ~/ 2,
    (i) => data.getInt16(i * 2, Endian.little) / 32768,
  );
  final frame = ExperimentalCodec().encode('wookiemeat');
  if (corrupt) frame[6] ^= 0x80;
  final bits = [
    for (final byte in frame)
      for (var b = 7; b >= 0; b--) (byte >> b) & 1,
  ];
  for (var repeat = 0; repeat < 3; repeat++) {
    final start = 24000 + repeat * (24000 + 144 * 3840);
    if (single && repeat > 0) {
      samples.fillRange(start, start + 144 * 3840, 0.0);
      continue;
    }
    // Captured-path fixture only: retain every 160 ms pair's overall timing,
    // but join opposite tones into 65+60 = 125 ms with no quiet boundary.
    for (var symbol = 0; symbol < bits.length; symbol++) {
      final at = start + symbol * 3840;
      if (symbol + 1 < bits.length && bits[symbol] != bits[symbol + 1]) {
        final replacement = [
          ...tone(65, bits[symbol]),
          ...tone(60, bits[symbol + 1]),
          ...List.filled(35 * 48, 0.0),
        ];
        samples.setRange(at, at + replacement.length, replacement);
        symbol++;
      } else if (corrupt && symbol == 48) {
        samples.setRange(at, at + 1920, tone(40, bits[symbol]));
      }
    }
  }
  return samples;
}

void main() {
  test('125 ms with no frequency transition remains too long', () {
    final detector = detect([...tone(125, 1), ...List.filled(1920, 0.0)]);
    expect(detector.diagnostics.transitionBoundaries, 0);
    expect(detector.diagnostics.acceptedSymbols, 0);
    expect(detector.diagnostics.longBursts, 1);
  });
  test('125 ms joined 1 then 0 runs split into two valid symbols', () {
    final detector = detect([
      ...tone(65, 1),
      ...tone(60, 0),
      ...List.filled(1920, 0.0),
    ]);
    expect(detector.diagnostics.acceptedSymbols, 2);
    expect(detector.diagnostics.trace.first.map((r) => r.bit), [1, 0]);
    expect(detector.diagnostics.trace.first.map((r) => r.toneMs), [65, 60]);
    expect(detector.diagnostics.trace.first[1].gapMs, 0);
    expect(detector.diagnostics.longBursts, 0);
    expect(detector.diagnostics.transitionBoundaries, 1);
    expect(detector.diagnostics.candidateBlocks, 25);
    expect(detector.diagnostics.trace.first.first.boundary, 'frequency');
    expect(detector.diagnostics.trace.first.last.boundary, 'quiet');
  });
  test('reverse 0 then 1 transition also segments', () {
    final detector = detect([
      ...tone(65, 0),
      ...tone(60, 1),
      ...List.filled(1920, 0.0),
    ]);
    expect(detector.diagnostics.trace.first.map((r) => r.bit), [0, 1]);
    expect(detector.diagnostics.acceptedSymbols, 2);
  });
  test(
    'D04 15 one votes plus 10 zero votes split but 75 ms run stays rejected',
    () {
      final detector = detect([
        ...tone(75, 1),
        ...tone(50, 0),
        ...List.filled(1920, 0.0),
      ]);
      expect(detector.diagnostics.trace.first.map((r) => r.toneMs), [75, 50]);
      expect(detector.diagnostics.trace.first.map((r) => r.status), [
        'LONG',
        'ACCEPT',
      ]);
      expect(detector.diagnostics.acceptedSymbols, 1);
    },
  );
  test('one opposite 5 ms bin does not manufacture a boundary', () {
    final detector = detect([
      ...tone(20, 1),
      ...tone(5, 0),
      ...tone(15, 1),
      ...List.filled(1920, 0.0),
    ]);
    expect(detector.diagnostics.acceptedSymbols, 1);
    expect(detector.diagnostics.trace.first.single.bit, 1);
    expect(detector.diagnostics.trace.first.single.toneMs, 40);
  });
  test('single-bin reversal before silence is flushed once', () {
    final detector = detect([
      ...tone(35, 1),
      ...tone(5, 0),
      ...List.filled(1920, 0.0),
    ]);
    expect(detector.diagnostics.acceptedSymbols, 1);
    expect(detector.diagnostics.trace.first.single.toneMs, 40);
  });
  test('actual WAV with merged opposite-frequency pairs recovers frames', () {
    for (final offset in [0, 71, 239]) {
      final received = <String>[];
      final detector = detect(
        mergedWav(),
        offset: offset,
        onBeacon: (p, _) => received.add(p),
      );
      expect(detector.diagnostics.preamblesFound, 3);
      expect(detector.diagnostics.acceptedFrames, 3);
      expect(detector.diagnostics.checksum, 'PASS');
      expect(detector.diagnostics.payload, 'wookiemeat');
      expect(received, ['wookiemeat']);
    }
  });
  test('merged runs still require valid CRC', () {
    final detector = detect(
      mergedWav(corrupt: true),
      onBeacon: (_, _) => fail('Corruption accepted'),
    );
    expect(detector.diagnostics.preamblesFound, 3);
    expect(detector.diagnostics.crcFailures, 3);
    expect(detector.diagnostics.acceptedFrames, 0);
  });
  test('merged runs still require two matching frames', () {
    final detector = detect(
      mergedWav(single: true),
      onBeacon: (_, _) => fail('Single frame accepted'),
    );
    expect(detector.diagnostics.acceptedFrames, 1);
    expect(detector.diagnostics.validatedBeacons, 0);
  });
}
