import 'dart:math';
import '../protocol/beacon_protocol.dart';

class SignalDiagnostics {
  double frequency = 0, level = 0, confidence = 0;
  bool candidate = false, preamble = false;
  String checksum = 'Waiting', payload = '';
  int acceptedFrames = 0, rejectedFrames = 0;
  // Session-only measurements. None participates in a decoding decision.
  int processedSamples = 0, candidateBlocks = 0, quietBlocks = 0;
  int acceptedSymbols = 0, shortBursts = 0, longBursts = 0;
  int preamblesFound = 0, invalidHeaders = 0, crcFailures = 0;
  int validatedBeacons = 0, matchingFrames = 0;
  double peakLevel = 0;
  final recentBurstMs = <int>[];
}

class BeaconDetector {
  final BeaconConfig config;
  final BeaconCodec codec;
  final void Function(String, double) onBeacon;
  final diagnostics = SignalDiagnostics();
  final _pending = <double>[];
  final _bits = <int>[];
  int _clock = 0, _lastTone = 0, _toneHops = 0, _quietHops = 0, _ones = 0;
  int _sync = 0, _lastFrame = -10000000, _matches = 0;
  String? _previous;
  double _quality = 0;
  BeaconDetector(this.config, this.onBeacon, {BeaconCodec? codec})
    : codec = codec ?? ExperimentalCodec() {
    config.validate();
  }

  void add(List<double> samples) {
    _pending.addAll(samples);
    const hop = 240;
    var offset = 0;
    while (_pending.length - offset >= hop) {
      _process(_pending.sublist(offset, offset + hop));
      offset += hop;
    }
    if (offset > 0) {
      _pending.removeRange(0, offset);
    }
  }

  double _amplitude(List<double> samples, double hz) {
    final coefficient = 2 * cos(2 * pi * hz / config.sampleRate);
    double previous = 0, older = 0, windowSum = 0;
    for (var i = 0; i < samples.length; i++) {
      final window = .5 - .5 * cos(2 * pi * i / (samples.length - 1));
      final current = samples[i] * window + coefficient * previous - older;
      older = previous;
      previous = current;
      windowSum += window;
    }
    return 2 *
        sqrt(
          max(
            0,
            previous * previous +
                older * older -
                coefficient * previous * older,
          ),
        ) /
        windowSum;
  }

  void _process(List<double> samples) {
    _clock += samples.length;
    final zero = _amplitude(samples, config.zeroHz),
        one = _amplitude(samples, config.oneHz);
    final strength = max(zero, one);
    final confidence = strength / (zero + one + 1e-12);
    diagnostics.processedSamples += samples.length;
    diagnostics.peakLevel = max(diagnostics.peakLevel, strength);
    diagnostics
      ..frequency = zero > one ? config.zeroHz : config.oneHz
      ..level = strength
      ..confidence = confidence
      ..candidate =
          strength >= config.threshold && confidence >= config.confidence;
    if (diagnostics.candidate) {
      diagnostics.candidateBlocks++;
      _lastTone = _clock;
      _quietHops = 0;
      _toneHops++;
      _ones += one > zero ? 1 : 0;
      _quality += confidence;
    } else {
      diagnostics.quietBlocks++;
      _quietHops++;
      if (_quietHops == 2 && _toneHops > 0) {
        final durationMs = _toneHops * 5;
        diagnostics.recentBurstMs.add(durationMs);
        if (diagnostics.recentBurstMs.length > 20) {
          diagnostics.recentBurstMs.removeAt(0);
        }
        if (durationMs >= config.symbolMs * .25 &&
            durationMs <= config.symbolMs * .75) {
          diagnostics.acceptedSymbols++;
          _bit(_ones * 2 > _toneHops ? 1 : 0, _quality / _toneHops);
        } else {
          if (durationMs < config.symbolMs * .25) {
            diagnostics.shortBursts++;
          } else {
            diagnostics.longBursts++;
          }
          _resetFrame();
        }
        _toneHops = 0;
        _ones = 0;
        _quality = 0;
      }
    }
    if (_clock - _lastTone > config.sampleRate * config.symbolMs * 2 / 1000) {
      _resetFrame();
    }
  }

  void _resetFrame() {
    _bits.clear();
    _sync = 0;
    diagnostics.preamble = false;
  }

  void _bit(int bit, double confidence) {
    if (!diagnostics.preamble) {
      _sync = ((_sync << 1) | bit) & 0xffffffff;
      if (_sync == 0xd391a65c) {
        diagnostics.preamblesFound++;
        diagnostics.preamble = true;
        _bits.clear();
      }
      return;
    }
    _bits.add(bit);
    if (_bits.length % 8 != 0) {
      return;
    }
    final bytes = <int>[];
    for (var i = 0; i < _bits.length; i += 8) {
      var byte = 0;
      for (var j = 0; j < 8; j++) {
        byte = (byte << 1) | _bits[i + j];
      }
      bytes.add(byte);
    }
    if (bytes.length < 2) {
      return;
    }
    if (bytes[0] != 1 || bytes[1] < 1 || bytes[1] > 64) {
      diagnostics.invalidHeaders++;
      diagnostics.rejectedFrames++;
      _resetFrame();
      return;
    }
    if (bytes.length != bytes[1] + 4) {
      return;
    }
    final payload = codec.decode(bytes);
    diagnostics.checksum = payload == null ? 'FAIL' : 'PASS';
    if (payload == null) {
      diagnostics.crcFailures++;
      diagnostics.rejectedFrames++;
      _previous = null;
      _matches = 0;
      diagnostics.matchingFrames = 0;
    } else {
      diagnostics.acceptedFrames++;
      diagnostics.payload = payload;
      final maxGap =
          config.sampleRate *
          (config.symbolMs * (bytes.length + 4) * 8 / 1000 + 3);
      _matches = payload == _previous && _clock - _lastFrame <= maxGap
          ? _matches + 1
          : 1;
      _previous = payload;
      _lastFrame = _clock;
      diagnostics.matchingFrames = _matches;
      if (_matches >= config.repeats) {
        diagnostics.validatedBeacons++;
        onBeacon(payload, confidence);
        _matches = 0;
      }
    }
    _resetFrame();
  }
}
