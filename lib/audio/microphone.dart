import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

abstract interface class PcmCapture {
  Future<Stream<List<double>>> start();
  Future<void> stop();
  Future<void> dispose();
}

class MicrophoneCapture implements PcmCapture {
  AudioRecorder? _instance;
  AudioRecorder get _recorder => _instance ??= AudioRecorder();
  @override
  Future<Stream<List<double>>> start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError(
        'Microphone permission is needed. Enable it in your phone settings, then try again.',
      );
    }
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 48000,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ),
    );
    int? carry;
    return stream.map((chunk) {
      final bytes = Uint8List.fromList([if (carry != null) carry!, ...chunk]);
      carry = bytes.length.isOdd ? bytes.last : null;
      final data = ByteData.sublistView(bytes);
      return List.generate(
        bytes.length ~/ 2,
        (i) => data.getInt16(i * 2, Endian.little) / 32768,
      );
    });
  }

  @override
  Future<void> stop() async {
    await _instance?.stop();
  }

  @override
  Future<void> dispose() async {
    await _instance?.dispose();
  }
}
