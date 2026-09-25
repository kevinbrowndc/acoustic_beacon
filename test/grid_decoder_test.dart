import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:acoustic_beacon/dsp/detector.dart';
import 'package:acoustic_beacon/dsp/grid_decoder.dart';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';

const audible = BeaconConfig(zeroHz: 4000, oneHz: 5000);

// Received-path fixtures only: the transmitted protocol and delivery WAV stay
// unchanged. Each slot still represents the original frame bit on an 80 ms grid.
List<double> observed(String shape, {List<int>? frame, int repeats = 3}) {
  final bytes = frame ?? ExperimentalCodec().encode('wookiemeat');
  final result = <double>[];
  for (var repeat = 0; repeat < repeats; repeat++) {
    result.addAll(List.filled(24000, 0.0));
    var symbol = 0;
    for (final byte in bytes) {
      for (var bit = 7; bit >= 0; bit--, symbol++) {
        final hz = ((byte >> bit) & 1) == 0 ? 4000 : 5000;
        final fragmented =
            shape == 'fragmented' || (shape == 'mixed' && symbol % 3 == 0);
        for (var i = 0; i < 3840; i++) {
          final active = !fragmented || (i ~/ 240) % 3 == 0;
          result.add(active ? .4 * sin(2 * pi * hz * i / 48000) : 0.0);
        }
      }
    }
  }
  result.addAll(List.filled(24000, 0.0));
  return result;
}

BeaconDetector replay(
  List<double> samples, {
  int offset = 0,
  List<String>? received,
}) {
  final detector = BeaconDetector(audible, (p, _) => received?.add(p));
  detector.add(List.filled(offset, 0.0));
  // Exercise both sub-hop and multiple-hop callbacks.
  const chunks = [71, 1993, 480, 7, 4096];
  var i = 0, n = 0;
  while (i < samples.length) {
    final end = min(i + chunks[n++ % chunks.length], samples.length);
    detector.add(samples.sublist(i, end));
    i = end;
  }
  return detector;
}

void main() {
  for (final shape in ['fragmented', 'joined', 'mixed']) {
    test('grid recovers $shape observations at arbitrary phases', () {
      final pcm = observed(shape);
      for (final offset in [0, 71, 239, 769, 2003, 3777]) {
        final received = <String>[];
        final detector = replay(pcm, offset: offset, received: received);
        final d = detector.diagnostics;
        expect(d.preamblesFound, 3, reason: '$shape offset $offset');
        expect(d.acceptedFrames, 3);
        expect(d.checksum, 'PASS');
        expect(d.payload, 'wookiemeat');
        expect(received, ['wookiemeat']);
        expect(d.grid.bestHamming, 0);
        expect(d.grid.recoveredPreamble, '11010011100100011010011001011100');
        expect(d.grid.locks, 3);
        expect(d.grid.locked, isFalse);
        expect(d.grid.bestOffsetMs, inInclusiveRange(0, 79.999));
        expect(d.grid.observations, lessThanOrEqualTo(d.grid.capacity));
        if (shape == 'fragmented') {
          expect(d.shortBursts + d.longBursts, greaterThan(0));
        }
        if (shape == 'joined') expect(d.longBursts, greaterThan(0));
      }
    });
  }
  test('starting midway through a symbol reacquires the next two frames', () {
    final received = <String>[];
    final pcm = observed('joined');
    final detector = replay(
      pcm.sublist(24000 + 17 * 3840 + 137),
      received: received,
    );
    expect(detector.diagnostics.acceptedFrames, 2);
    expect(received, ['wookiemeat']);
  });
  test('one incorrect preamble bit never establishes timing lock', () {
    final bytes = ExperimentalCodec().encode('wookiemeat');
    bytes[0] ^= 1;
    final detector = replay(observed('joined', frame: bytes));
    expect(detector.diagnostics.grid.bestHamming, 1);
    expect(detector.diagnostics.grid.locks, 0);
    expect(detector.diagnostics.preamblesFound, 0);
    expect(detector.diagnostics.acceptedFrames, 0);
    expect(detector.diagnostics.payload, '');
  });
  test('joined grid does not bypass CRC or repeated-frame gates', () {
    final bytes = ExperimentalCodec().encode('wookiemeat');
    bytes.last ^= 1;
    final corrupted = replay(observed('joined', frame: bytes));
    expect(corrupted.diagnostics.grid.locks, 3);
    expect(corrupted.diagnostics.crcFailures, 3);
    expect(corrupted.diagnostics.validatedBeacons, 0);
    final single = replay(observed('fragmented', repeats: 1));
    expect(single.diagnostics.acceptedFrames, 1);
    expect(single.diagnostics.validatedBeacons, 0);
  });
  test('invalid header releases lock without delivering payload', () {
    final bytes = ExperimentalCodec().encode('wookiemeat');
    bytes[4] = 2;
    final detector = replay(observed('joined', frame: bytes));
    expect(detector.diagnostics.invalidHeaders, 3);
    expect(detector.diagnostics.acceptedFrames, 0);
    expect(detector.diagnostics.grid.locked, isFalse);
  });
  test('missing locked slot abandons frame then reacquires', () {
    final pcm = observed('joined');
    pcm.fillRange(24000 + 38 * 3840, 24000 + 39 * 3840, 0.0);
    final received = <String>[];
    final detector = replay(pcm, received: received);
    expect(detector.diagnostics.grid.missingSlots, 1);
    expect(detector.diagnostics.acceptedFrames, 2);
    expect(received, ['wookiemeat']);
  });
  test(
    'longest supported payload is decoded beyond the rolling buffer length',
    () {
      final received = <String>[];
      final bytes = ExperimentalCodec().encode('x' * 64);
      final detector = replay(
        observed('joined', frame: bytes, repeats: 2),
        received: received,
      );
      expect(detector.diagnostics.acceptedFrames, 2);
      expect(received, ['x' * 64]);
      expect(detector.diagnostics.grid.capacity, 546);
    },
  );
  test('observation storage stays bounded over a long idle session', () {
    final grid = GridDecoder(
      audible,
      onLock: () => fail('silence lock'),
      onFrame: (_, _, _) => fail('silence frame'),
      onReject: (_) {},
    );
    for (var i = 0; i < 120000; i++) {
      grid.add(0, 0, false);
    }
    expect(grid.diagnostics.observations, 546);
    expect(grid.diagnostics.capacity, 546);
    expect(grid.diagnostics.bestHamming, 33);
  });
}
