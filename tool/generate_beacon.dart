import 'dart:io';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';

void main(List<String> args) {
  String? option(String name) {
    final prefix = '--$name=';
    final matches = args.where((e) => e.startsWith(prefix));
    return matches.isEmpty ? null : matches.single.substring(prefix.length);
  }

  final audible = args.contains('--audible');
  final config = BeaconConfig(
    zeroHz: double.parse(option('zero-hz') ?? (audible ? '4000' : '20000')),
    oneHz: double.parse(option('one-hz') ?? (audible ? '5000' : '21000')),
    symbolMs: int.parse(option('symbol-ms') ?? '80'),
  );
  config.validate();
  final repetitions = int.parse(option('repetitions') ?? '3');
  final amplitude = double.parse(option('amplitude') ?? '0.6');
  if (repetitions < 1 ||
      repetitions > 10 ||
      !amplitude.isFinite ||
      amplitude <= 0 ||
      amplitude > 1) {
    throw ArgumentError('Repetitions must be 1–10 and amplitude > 0 and <= 1');
  }
  final path =
      option('output') ??
      (audible ? 'beacon-audible.wav' : 'beacon-ultrasonic.wav');
  final payload = option('payload') ?? 'wookiemeat';
  File(path).writeAsBytesSync(
    wav(
      synthesize(
        config,
        ExperimentalCodec().encode(payload),
        repetitions: repetitions,
        amplitude: amplitude,
      ),
      config.sampleRate,
    ),
  );
  stdout.writeln(
    'Created $path (${config.zeroHz}/${config.oneHz} Hz, ${config.symbolMs} ms symbols, $repetitions frames, payload $payload; 48 kHz mono PCM16).',
  );
}
