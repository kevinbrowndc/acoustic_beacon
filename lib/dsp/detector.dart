import 'dart:math';
import '../protocol/beacon_protocol.dart';
import 'receiver_trace.dart';
import 'grid_decoder.dart';

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
  int transitionBoundaries = 0;
  double peakLevel = 0;
  final recentBurstMs = <int>[];
  final trace = ReceiverTrace();
  late GridDiagnostics grid;
}

class BeaconDetector {
  final BeaconConfig config;
  final BeaconCodec codec;
  final void Function(String, double) onBeacon;
  final diagnostics = SignalDiagnostics();
  final _pending = <double>[];
  final _bits = <int>[];
  late final GridDecoder _grid;
  bool _burstPreamble = false;
  int _clock = 0, _lastTone = 0, _toneHops = 0, _quietHops = 0, _ones = 0;
  int _sync = 0, _lastFrame = -10000000, _matches = 0;
  String? _previous;
  double _quality = 0;
  int _traceStart = 0, _traceGap = 0;
  String _traceRun = '';
  int _traceTransitions = 0, _traceLastBit = -1;
  final _transition = <({int bit, double confidence, int clock})>[];
  BeaconDetector(this.config, this.onBeacon, {BeaconCodec? codec})
    : codec = codec ?? ExperimentalCodec() {
    config.validate();
    _grid = GridDecoder(
      config,
      onLock: () {
        diagnostics.preamblesFound++;
      },
      onFrame: _gridFrame,
      codec: this.codec,
      onReject: (reason) {
        diagnostics.rejectedFrames++;
        if (reason == 'invalid header') diagnostics.invalidHeaders++;
      },
    );
    diagnostics.grid = _grid.diagnostics;
  }

  void finishInput() => _grid.finishInput();

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
    _grid.add(zero, one, diagnostics.candidate);
    diagnostics.preamble = _grid.diagnostics.locked;
    if (diagnostics.candidate) {
      diagnostics.candidateBlocks++;
      _quietHops = 0;
      final bit = one > zero ? 1 : 0;
      final previousBit = _ones * 2 > _toneHops ? 1 : 0;
      // Require a viable old run and two consecutive qualifying new-frequency
      // blocks. Buffer them so neither is counted in both symbols.
      if (_toneHops * 5 >= config.symbolMs * .25 && bit != previousBit) {
        _transition.add((bit: bit, confidence: confidence, clock: _clock));
        if (_transition.length == 2) {
          diagnostics.transitionBoundaries++;
          _finishTone('frequency');
          _flushTransition();
        }
      } else {
        _flushTransition();
        _appendTone(bit, confidence, _clock);
      }
    } else {
      diagnostics.quietBlocks++;
      // One opposite bin followed by quiet is not a stable transition.
      _flushTransition();
      _quietHops++;
      if (_quietHops == 2 && _toneHops > 0) _finishTone('quiet');
    }
    diagnostics.trace.openBurst = _toneHops == 0
        ? 'none'
        : 'tone ${_toneHops * 5} ms / 0:${_toneHops - _ones} 1:$_ones / quiet ${_quietHops * 5} ms';
    if (_clock - _lastTone > config.sampleRate * config.symbolMs * 2 / 1000) {
      _resetFrame('idle timeout');
    }
  }

  void _appendTone(int bit, double confidence, int endClock) {
    if (_toneHops == 0) {
      _traceStart = endClock - 240;
      _traceGap = ((_traceStart - _lastTone) * 1000 / config.sampleRate)
          .round();
      _traceRun = '';
      _traceTransitions = 0;
      _traceLastBit = -1;
    }
    if (_traceLastBit >= 0 && bit != _traceLastBit) _traceTransitions++;
    _traceLastBit = bit;
    if (_traceRun.length < 80) _traceRun += '$bit';
    _lastTone = endClock;
    _toneHops++;
    _ones += bit;
    _quality += confidence;
  }

  void _flushTransition() {
    for (final hop in _transition) {
      _appendTone(hop.bit, hop.confidence, hop.clock);
    }
    _transition.clear();
  }

  void _finishTone(String boundary) {
    final durationMs = _toneHops * 5;
    final traceBefore = diagnostics.trace.rolling;
    final tracePhase = _burstPreamble ? 'DATA' : 'SYNC';
    var traceStatus = 'ACCEPT';
    diagnostics.recentBurstMs.add(durationMs);
    if (diagnostics.recentBurstMs.length > 20) {
      diagnostics.recentBurstMs.removeAt(0);
    }
    // A reflection can extend the 40 ms transmitted tone into its silent
    // half. Accept it while two quiet hops still separate 80 ms symbols.
    // Do not extend the symbol clock or accept a full-symbol carrier.
    final minimumGapMs = 2 * 240 * 1000 / config.sampleRate;
    if (durationMs >= config.symbolMs * .25 &&
        durationMs <= config.symbolMs - minimumGapMs) {
      diagnostics.acceptedSymbols++;
      _bit(_ones * 2 > _toneHops ? 1 : 0, _quality / _toneHops);
    } else {
      if (durationMs < config.symbolMs * .25) {
        // Too brief to be a symbol: ignore interference between tones.
        // A missing real symbol still fails framing/CRC; long bursts and
        // the existing idle timeout still discard incomplete frames.
        traceStatus = 'SHORT';
        diagnostics.shortBursts++;
      } else {
        traceStatus = 'LONG';
        diagnostics.longBursts++;
        _resetFrame('long burst');
      }
    }
    diagnostics.trace.record(
      BurstTrace(
        number: diagnostics.trace.totalBursts + 1,
        timeMs: (_traceStart * 1000 / config.sampleRate).round(),
        bit: _ones * 2 > _toneHops ? 1 : 0,
        toneMs: durationMs,
        spanMs: ((_lastTone - _traceStart) * 1000 / config.sampleRate).round(),
        gapMs: _traceGap,
        zeros: _toneHops - _ones,
        ones: _ones,
        transitions: _traceTransitions,
        run: _traceRun,
        status: traceStatus,
        phase: tracePhase,
        before: traceBefore,
        after: diagnostics.trace.rolling,
        boundary: boundary,
      ),
    );
    _toneHops = 0;
    _ones = 0;
    _quality = 0;
  }

  void _resetFrame([String reason = 'frame complete']) {
    diagnostics.trace.reset(reason);
    _bits.clear();
    _sync = 0;
    _burstPreamble = false;
  }

  void _bit(int bit, double confidence) {
    if (!_burstPreamble) {
      _sync = ((_sync << 1) | bit) & 0xffffffff;
      diagnostics.trace.compare(bit, _sync);
      if (_sync == 0xd391a65c) {
        _burstPreamble = true;
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
      _resetFrame('invalid header');
      return;
    }
    if (bytes.length != bytes[1] + 4) {
      return;
    }
    final payload = codec.decode(bytes);
    _resetFrame(payload == null ? 'CRC/payload failure' : 'frame complete');
  }

  void _gridFrame(List<int> bytes, double confidence, int frameEnd) {
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
      _matches = payload == _previous && frameEnd - _lastFrame <= maxGap
          ? _matches + 1
          : 1;
      _previous = payload;
      _lastFrame = frameEnd;
      diagnostics.matchingFrames = _matches;
      if (_matches >= config.repeats) {
        diagnostics.validatedBeacons++;
        _grid.markValidated();
        onBeacon(payload, confidence);
        _matches = 0;
      }
    }
  }
}
