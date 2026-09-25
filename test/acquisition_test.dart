import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:acoustic_beacon/dsp/grid_decoder.dart';
import 'package:acoustic_beacon/dsp/detector.dart';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';
import 'fixtures/d06_grid_decoder.dart' as baseline;
import 'wav_replay_test.dart' show readPcm;

const config = BeaconConfig(zeroHz: 4000, oneHz: 5000);
typedef Observation = ({double zero, double one, bool candidate});
const quiet = (zero: 0.0, one: 0.0, candidate: false);
Observation tone(int bit) =>
    (zero: bit == 0 ? .4 : 0.0, one: bit == 1 ? .4 : 0.0, candidate: true);
List<Observation> observations({
  List<int>? frame,
  int repetitions = 3,
  int lead = 100,
  bool joined = false,
}) {
  final bytes = frame ?? ExperimentalCodec().encode('wookiemeat');
  final output = <Observation>[];
  for (var r = 0; r < repetitions; r++) {
    output.addAll(List.filled(lead, quiet));
    for (final byte in bytes) {
      for (var bit = 7; bit >= 0; bit--) {
        for (var hop = 0; hop < 16; hop++) {
          output.add(joined || hop < 8 ? tone((byte >> bit) & 1) : quiet);
        }
      }
    }
  }
  output.addAll(List.filled(100, quiet));
  return output;
}

void feed(GridDecoder grid, Iterable<Observation> input) {
  for (final o in input) {
    grid.add(o.zero, o.one, o.candidate);
  }
}

GridDecoder create({
  void Function()? lock,
  void Function(List<int>, double, int)? frame,
}) => GridDecoder(
  config,
  onLock: lock ?? () {},
  onFrame: frame ?? (_, _, _) {},
  onReject: (_) {},
);

void main() {
  test('D07 locks on the first exact 32-slot window, before buffer fills', () {
    var tick = 0, newLock = -1, oldLock = -1;
    final fresh = create(
      lock: () {
        if (newLock < 0) newLock = tick;
      },
    );
    final old = baseline.GridDecoder(
      config,
      onLock: () {
        if (oldLock < 0) oldLock = tick;
      },
      onFrame: (_, _, _) {},
      onReject: (_) {},
    );
    final input = observations(repetitions: 1, lead: 0, joined: true);
    for (final o in input) {
      tick++;
      fresh.add(o.zero, o.one, o.candidate);
      old.add(o.zero, o.one, o.candidate);
      if (tick == 8 * 16) {
        expect(fresh.diagnostics.preferredOffsetMs, isNotNull);
      }
      if (tick == 32 * 16) {
        expect(newLock, 512);
        expect(
          fresh.diagnostics.observations,
          lessThan(fresh.diagnostics.capacity),
        );
        expect(oldLock, -1);
      }
    }
    expect((oldLock - newLock) * 5, 80);
    expect(fresh.diagnostics.validFrames, 1);
    expect(fresh.diagnostics.signalToLockMs, 2560);
    expect(
      fresh.diagnostics.signalToPayloadMs,
      fresh.diagnostics.signalToLockMs! + fresh.diagnostics.lockToPayloadMs!,
    );
    // ignore: avoid_print
    print(
      'Lock comparison: D06=${oldLock * 5} ms; D07=${newLock * 5} ms; saved=${(oldLock - newLock) * 5} ms',
    );
  });
  test(
    'incremental search evaluates each new slot once rather than rescanning 32',
    () {
      final bytes = ExperimentalCodec().encode('wookiemeat')..[0] ^= 1;
      final input = observations(frame: bytes, joined: true);
      final fresh = create();
      final old = baseline.GridDecoder(
        config,
        onLock: () => fail('bad preamble'),
        onFrame: (_, _, _) => fail('bad preamble'),
        onReject: (_) {},
      );
      for (final o in input) {
        fresh.add(o.zero, o.one, o.candidate);
        old.add(o.zero, o.one, o.candidate);
      }
      expect(fresh.diagnostics.locks, 0);
      expect(fresh.diagnostics.bestHamming, 1);
      expect(fresh.diagnostics.timingOffsetsTested, 16);
      expect(
        fresh.diagnostics.slotEvaluations,
        fresh.diagnostics.offsetEvaluations,
      );
      expect(
        old.slotEvaluations,
        greaterThan(fresh.diagnostics.slotEvaluations * 8),
      );
      // ignore: avoid_print
      print(
        'No-lock slot evaluations: D06=${old.slotEvaluations}, D07=${fresh.diagnostics.slotEvaluations}',
      );
    },
  );
  test(
    'nearby exact phases rescue an early phase without a replay or duplicate frame',
    () {
      final input = observations();
      const frameHops = 144 * 16;
      for (var repeat = 0; repeat < 3; repeat++) {
        final start = 100 + repeat * (100 + frameHops) + 36 * 16;
        // Same zero bit, usable evidence delayed inside its slot. The earliest
        // exact phase misses it; the known-good phase still has 30 ms evidence.
        for (var i = 0; i < 16; i++) {
          input[start + i] = i >= 9 && i < 15 ? tone(0) : quiet;
        }
      }
      final payloads = <String>[];
      final fresh = create(
        frame: (b, _, _) {
          final p = ExperimentalCodec().decode(b);
          if (p != null) payloads.add(p);
        },
      );
      feed(fresh, input);
      expect(payloads, ['wookiemeat', 'wookiemeat', 'wookiemeat']);
      expect(fresh.diagnostics.failedCandidates, greaterThan(0));
      expect(fresh.diagnostics.locks, 3);
      expect(fresh.diagnostics.validFrames, 3);
      expect(fresh.diagnostics.observations, fresh.diagnostics.capacity);
    },
  );
  test(
    'identical actual WAV playbacks give identical payloads and latencies',
    () {
      final data = ByteData.sublistView(readPcm());
      final pcm = List.generate(
        data.lengthInBytes ~/ 2,
        (i) => data.getInt16(i * 2, Endian.little) / 32768,
      );
      final timings = <List<double?>>[];
      for (var trial = 0; trial < 8; trial++) {
        final received = <String>[];
        final detector = BeaconDetector(config, (p, _) => received.add(p));
        detector.add(List.filled(1737, 0.0));
        var position = 0;
        final chunks = [71, 997, 4096, 239, 1601];
        while (position < pcm.length) {
          final end = min(
            position + chunks[(position + trial) % chunks.length],
            pcm.length,
          );
          detector.add(pcm.sublist(position, end));
          position = end;
        }
        detector.finishInput();
        final d = detector.diagnostics;
        expect(received, ['wookiemeat']);
        expect(d.acceptedFrames, 3);
        expect(d.grid.totalDetectionMs, isNotNull);
        timings.add([
          d.grid.signalToLockMs,
          d.grid.lockToPayloadMs,
          d.grid.signalToPayloadMs,
          d.grid.totalDetectionMs,
        ]);
        expect(timings.last, timings.first);
      }
      // ignore: avoid_print
      print(
        'Actual WAV 8/8 consistent; audio-time ms [lock, lock-to-payload, first payload, validated]: ${timings.first}',
      );
    },
  );
  test(
    'successive identical WAVs remain repeatable in one listening session',
    () {
      final pcm = ByteData.sublistView(readPcm());
      final input = List.generate(
        pcm.lengthInBytes ~/ 2,
        (i) => pcm.getInt16(i * 2, Endian.little) / 32768,
      );
      final received = <String>[];
      final detector = BeaconDetector(config, (p, _) => received.add(p));
      for (var i = 0; i < 4; i++) {
        detector.add(input);
        detector.add(List.filled(48000 * 2, 0.0));
      }
      expect(detector.diagnostics.acceptedFrames, 12);
      // Three frames per playback: repeat gate emits every second matching frame.
      expect(received, List.filled(6, 'wookiemeat'));
    },
  );
  test(
    'failure diagnostics distinguish silence, insufficient evidence and wrong preamble',
    () {
      final silent = create();
      feed(silent, List.filled(800, quiet));
      silent.finishInput();
      expect(silent.diagnostics.outcome, contains('No observations'));
      final short = create();
      feed(short, observations().take(100 + 10 * 16));
      short.finishInput();
      expect(short.diagnostics.outcome, contains('Insufficient consecutive'));
      final bytes = ExperimentalCodec().encode('wookiemeat')..[0] ^= 1;
      final wrong = create();
      feed(wrong, observations(frame: bytes));
      wrong.finishInput();
      expect(wrong.diagnostics.outcome, contains('No exact preamble'));
      expect(wrong.diagnostics.bestHamming, 1);
    },
  );
  test(
    'failure diagnostics retain CRC, invalid-header and incomplete-frame reasons',
    () {
      final badCrc = ExperimentalCodec().encode('wookiemeat');
      badCrc.last ^= 1;
      final crc = create();
      feed(crc, observations(frame: badCrc));
      crc.finishInput();
      expect(crc.diagnostics.outcome, contains('CRC or UTF-8'));
      expect(crc.diagnostics.validFrames, 0);
      final badHeader = ExperimentalCodec().encode('wookiemeat')..[4] = 2;
      final header = create();
      feed(header, observations(frame: badHeader));
      header.finishInput();
      expect(header.diagnostics.outcome, contains('Invalid header'));
      final incomplete = create();
      feed(incomplete, observations().take(100 + 50 * 16));
      incomplete.finishInput();
      expect(
        incomplete.diagnostics.outcome,
        'Stopped with an incomplete locked frame',
      );
      final single = create();
      feed(single, observations(repetitions: 1));
      single.finishInput();
      expect(single.diagnostics.outcome, contains('awaiting matching repeat'));
    },
  );
  test('failed candidate preserves rolling data and later exact frames', () {
    final bytes = ExperimentalCodec().encode('wookiemeat')..[4] = 2;
    final input = [
      ...observations(frame: bytes, repetitions: 1),
      ...observations(repetitions: 2),
    ];
    final fresh = create();
    feed(fresh, input);
    expect(fresh.diagnostics.validFrames, 2);
    expect(fresh.diagnostics.locks, 3);
    expect(fresh.diagnostics.failureCounts['invalid header'], greaterThan(0));
    expect(fresh.diagnostics.observations, 546);
  });
}
