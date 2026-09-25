import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:acoustic_beacon/dsp/detector.dart';
import 'package:acoustic_beacon/dsp/receiver_trace.dart';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';
import 'package:acoustic_beacon/application/beacon_controller.dart';
import 'package:acoustic_beacon/data/content.dart';
import 'package:acoustic_beacon/presentation/app.dart';
import 'controller_test.dart' show TestCapture;

void main() {
  const config = BeaconConfig(zeroHz: 4000, oneHz: 5000);
  test('D05 records actual preamble bits, tone and preceding gap', () {
    final detector = BeaconDetector(config, (_, _) {});
    detector.add(synthesize(config, ExperimentalCodec().encode('wookiemeat')));
    final trace = detector.diagnostics.trace;
    expect(trace.totalBursts, 432);
    expect(trace.first.length, 64);
    expect(trace.recent.length, 128);
    expect(trace.first.first.bit, 1);
    expect(trace.first.first.toneMs, 40);
    expect(trace.first.first.spanMs, 40);
    expect(trace.first.first.gapMs, 500);
    expect(trace.first[1].gapMs, 40);
    expect(trace.first.first.after, '1');
    expect(trace.first[31].after, ReceiverTrace.expected);
    expect(trace.first[32].phase, 'DATA');
    expect(trace.first.every((row) => row.status == 'ACCEPT'), isTrue);
    expect(trace.best, ReceiverTrace.expected);
    expect(trace.bestErrors, 0);
    expect(trace.bestAt, 32);
    expect(trace.bestBursts.length, 32);
    expect(trace.bestBursts.last.after, ReceiverTrace.expected);
    expect(trace.lastReset, 'frame complete');
    expect(detector.diagnostics.acceptedFrames, 3);
    expect(detector.diagnostics.validatedBeacons, 1);
    final summary = trace.summary(4000, 5000);
    detector.add(List.filled(48000, 0.0));
    expect(trace.summary(4000, 5000), summary);
  });
  test(
    'D05 exposes short, long and unfinished bursts without accepting them',
    () {
      final detector = BeaconDetector(config, (_, _) => fail('invalid beacon'));
      List<double> tone(int ms, double hz) =>
          List.generate(ms * 48, (i) => .5 * sin(2 * pi * hz * i / 48000));
      detector.add([
        ...tone(10, 4000),
        ...List.filled(960, 0.0),
        ...tone(100, 4000),
        ...List.filled(960, 0.0),
      ]);
      final rows = detector.diagnostics.trace.first;
      expect(rows[0].status, 'SHORT');
      expect(rows[0].toneMs, 10);
      expect(rows[1].status, 'LONG');
      expect(rows[1].toneMs, 100);
      expect(rows[1].gapMs, 20);
      expect(rows[1].zeros, 20);
      expect(rows[1].ones, 0);
      expect(rows[1].transitions, 0);
      expect(detector.diagnostics.acceptedSymbols, 0);
      detector.add(tone(90, 4000));
      expect(detector.diagnostics.trace.openBurst, contains('tone 90 ms'));
    },
  );
  test('D05 preserves rolling comparison before long-burst reset', () {
    final detector = BeaconDetector(config, (_, _) {});
    List<double> tone(int ms) =>
        List.generate(ms * 48, (i) => .5 * sin(2 * pi * 5000 * i / 48000));
    detector.add([
      ...tone(40),
      ...List.filled(1920, 0.0),
      ...tone(100),
      ...List.filled(48000, 0.0),
    ]);
    final trace = detector.diagnostics.trace;
    expect(trace.first[1].before, '1');
    expect(trace.first[1].after, '');
    expect(trace.lastCompared, '1');
    expect(trace.best, '');
    expect(trace.resetReasons['long burst'], 1);
    expect(trace.resets, 1);
  });
  testWidgets('D05 photo summary is visible on narrow debug screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = BeaconController(
      TestCapture(),
      LocalContentRepository(),
    );
    await controller.configure(config);
    controller.detector.add(
      synthesize(config, ExperimentalCodec().encode('wookiemeat')),
    );
    await tester.pumpWidget(
      MaterialApp(home: DebugPage(controller: controller)),
    );
    expect(find.text('Diagnostic build D07 diagnostic'), findsOneWidget);
    expect(find.textContaining('D07 TIMING GRID'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('D05 PHOTO SUMMARY'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('D05 PHOTO SUMMARY'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
