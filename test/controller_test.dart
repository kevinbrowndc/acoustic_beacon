import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:acoustic_beacon/application/beacon_controller.dart';
import 'package:acoustic_beacon/audio/microphone.dart';
import 'package:acoustic_beacon/data/content.dart';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';

class TestCapture implements PcmCapture {
  final stream = StreamController<List<double>>();
  bool denied = false;
  @override
  Future<Stream<List<double>>> start() async {
    if (denied) {
      throw StateError('Permission denied');
    }
    return stream.stream;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {
    await stream.close();
  }
}

void main() {
  test(
    'application only looks up content after repeated validated audio',
    () async {
      final capture = TestCapture();
      final controller = BeaconController(capture, LocalContentRepository());
      await controller.start();
      capture.stream.add(List.filled(48000, 0));
      await Future<void>.delayed(Duration.zero);
      expect(controller.content, isNull);
      capture.stream.add(
        synthesize(
          const BeaconConfig(),
          ExperimentalCodec().encode('wookiemeat'),
          repetitions: 2,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.content?.title, 'Beacon Detected');
      expect(controller.state, ListeningState.validBeacon);
      await controller.stop();
      expect(controller.active, isFalse);
      controller.dispose();
    },
  );
  test('permission denial is recoverable', () async {
    final capture = TestCapture()..denied = true;
    final controller = BeaconController(capture, LocalContentRepository());
    await controller.start();
    expect(controller.state, ListeningState.error);
    expect(controller.content, isNull);
    capture.denied = false;
    await controller.start();
    expect(controller.active, isTrue);
    await controller.stop();
    controller.dispose();
  });
}
