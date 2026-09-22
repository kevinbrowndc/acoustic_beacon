import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class BeaconConfig {
  final int sampleRate;
  final double zeroHz, oneHz, threshold, confidence;
  final int symbolMs, repeats;
  const BeaconConfig({
    this.sampleRate = 48000,
    this.zeroHz = 20000,
    this.oneHz = 21000,
    this.threshold = 0.008,
    this.confidence = 0.75,
    this.symbolMs = 80,
    this.repeats = 2,
  });
  void validate() {
    if (!zeroHz.isFinite ||
        !oneHz.isFinite ||
        !threshold.isFinite ||
        !confidence.isFinite ||
        sampleRate != 48000 ||
        zeroHz < 1000 ||
        oneHz < 1000 ||
        zeroHz >= sampleRate / 2 - 500 ||
        oneHz >= sampleRate / 2 - 500 ||
        (zeroHz - oneHz).abs() < 500 ||
        symbolMs < 60 ||
        symbolMs > 200 ||
        threshold <= 0 ||
        threshold > 0.5 ||
        confidence < .6 ||
        confidence > 1 ||
        repeats < 2) {
      throw ArgumentError('Invalid experimental signal configuration');
    }
  }
}

abstract interface class BeaconCodec {
  List<int> encode(String payload);
  String? decode(List<int> bytes);
}

class ExperimentalCodec implements BeaconCodec {
  static const sync = [0xd3, 0x91, 0xa6, 0x5c];
  static int crc(List<int> bytes) {
    var value = 0xffff;
    for (final byte in bytes) {
      value ^= byte << 8;
      for (var i = 0; i < 8; i++) {
        value = ((value << 1) ^ ((value & 0x8000) != 0 ? 0x1021 : 0)) & 0xffff;
      }
    }
    return value;
  }

  @override
  List<int> encode(String payload) {
    final data = utf8.encode(payload);
    if (data.isEmpty || data.length > 64) {
      throw ArgumentError('Payload must be 1–64 bytes');
    }
    final body = [1, data.length, ...data];
    final checksum = crc(body);
    return [...sync, ...body, checksum >> 8, checksum & 255];
  }

  @override
  String? decode(List<int> bytes) {
    if (bytes.length < 5 ||
        bytes[0] != 1 ||
        bytes[1] < 1 ||
        bytes[1] > 64 ||
        bytes.length != bytes[1] + 4) {
      return null;
    }
    if (crc(bytes.sublist(0, bytes.length - 2)) !=
        (bytes[bytes.length - 2] << 8 | bytes.last)) {
      return null;
    }
    try {
      return utf8.decode(bytes.sublist(2, bytes.length - 2));
    } on FormatException {
      return null;
    }
  }
}

List<double> synthesize(
  BeaconConfig config,
  List<int> frame, {
  int repetitions = 3,
  double amplitude = .6,
}) {
  config.validate();
  final n = config.sampleRate * config.symbolMs ~/ 1000;
  final result = <double>[];
  for (var repeat = 0; repeat < repetitions; repeat++) {
    result.addAll(List.filled(config.sampleRate ~/ 2, 0.0));
    for (final byte in frame) {
      for (var b = 7; b >= 0; b--) {
        final frequency = (byte >> b & 1) == 0 ? config.zeroHz : config.oneHz;
        for (var i = 0; i < n; i++) {
          final ramp = min(1.0, min(i / 96, (n ~/ 2 - i) / 96)).clamp(0.0, 1.0);
          result.add(
            i < n ~/ 2
                ? amplitude *
                      ramp *
                      sin(2 * pi * frequency * i / config.sampleRate)
                : 0.0,
          );
        }
      }
    }
  }
  result.addAll(List.filled(config.sampleRate ~/ 2, 0.0));
  return result;
}

Uint8List wav(List<double> samples, int rate) {
  final bytes = ByteData(44 + samples.length * 2);
  void tag(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bytes.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(
      44 + i * 2,
      (samples[i].clamp(-1, 1) * 32767).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}
