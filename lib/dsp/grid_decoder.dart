import 'dart:math';
import '../protocol/beacon_protocol.dart';

class GridDiagnostics {
  int observations = 0, capacity = 0, searches = 0, slotEvaluations = 0;
  int timingOffsetsTested = 0, offsetEvaluations = 0, longestUsableRun = 0;
  int bestHamming = 33, locks = 0, missingSlots = 0, failedCandidates = 0;
  int validFrames = 0;
  int? bestHammingBeforeLock;
  double? bestOffsetMs, lockedOffsetMs, preferredOffsetMs;
  double? signalToLockMs, lockToPayloadMs, signalToPayloadMs, totalDetectionMs;
  String bestPreamble = '', recoveredPreamble = '', lastUnlock = 'none';
  String lastFailure = '', decodedPayload = '';
  bool locked = false, stopped = false, usableSignalSeen = false;
  final failureCounts = <String, int>{};

  String get outcome {
    if (totalDetectionMs != null) return 'Validated matching frames';
    if (validFrames > 0) return 'CRC-valid payload; awaiting matching repeat';
    if (!usableSignalSeen) return 'No observations passed the signal gates';
    if (locked) {
      return stopped
          ? 'Stopped with an incomplete locked frame'
          : 'Locked frame still in progress';
    }
    if (lastFailure.isNotEmpty) return lastFailure;
    if (longestUsableRun < 32) {
      return 'Insufficient consecutive usable slots ($longestUsableRun/32)';
    }
    return 'No exact preamble (best Hamming $bestHamming/32)';
  }

  String _ms(double? value) =>
      value == null ? 'pending' : '${value.toStringAsFixed(1)} ms';
  String get summary =>
      'D07 TIMING GRID (5 ms search resolution)\n'
      'Rolling buffer: $observations/$capacity observations (${observations * 5} ms)\n'
      'Timing offsets tested: $timingOffsetsTested; evaluations: $offsetEvaluations\n'
      'Preferred offset: ${preferredOffsetMs?.toStringAsFixed(1) ?? "none"} ms\n'
      'Best timing offset: ${bestOffsetMs?.toStringAsFixed(1) ?? "none"} ms\n'
      'Best preamble: ${bestPreamble.isEmpty ? "none" : bestPreamble}\n'
      'Hamming distance: ${bestHamming == 33 ? "no full window" : "$bestHamming/32"}\n'
      'Best earlier Hamming before first lock: ${bestHammingBeforeLock == null || bestHammingBeforeLock == 33 ? "no earlier full window" : "$bestHammingBeforeLock/32"}\n'
      'Timing lock achieved: ${locks > 0 ? "YES ($locks)" : "NO"}; now ${locked ? "LOCKED" : "searching"}\n'
      'Last locked offset: ${lockedOffsetMs?.toStringAsFixed(1) ?? "none"} ms\n'
      'Recovered preamble: ${recoveredPreamble.isEmpty ? "none" : recoveredPreamble}\n'
      'Audio-time latency (from first usable signal):\n'
      'Signal -> first lock: ${_ms(signalToLockMs)}\n'
      'First lock -> first CRC-valid payload: ${_ms(lockToPayloadMs)}\n'
      'Signal -> first CRC-valid payload: ${_ms(signalToPayloadMs)}\n'
      'Total -> validated matching frames: ${_ms(totalDetectionMs)}\n'
      'Result / failure: $outcome\n'
      'Candidate failures: $failedCandidates $failureCounts\n'
      'Missing slots: $missingSlots; last unlock: $lastUnlock';
}

typedef _Slot = ({int bit, double confidence, double score});
typedef _Hit = ({int end, int phase, double score, int priorHamming});

class _Phase {
  final int phase;
  int next, word = 0, count = 0, prefix = 0, _position = 0;
  double score = 0;
  final _scores = List<double>.filled(32, 0);
  _Phase(this.phase, this.next);
  void add(_Slot? slot, List<int> failure) {
    if (slot == null) {
      word = count = prefix = _position = 0;
      score = 0;
      return;
    }
    word = ((word << 1) | slot.bit) & 0xffffffff;
    if (count == 32) score -= _scores[_position];
    _scores[_position] = slot.score;
    score += slot.score;
    _position = (_position + 1) % 32;
    if (count < 32) count++;
    if (prefix == 32) prefix = failure[31];
    while (prefix > 0 && slot.bit != GridDecoder.preambleBit(prefix)) {
      prefix = failure[prefix - 1];
    }
    if (slot.bit == GridDecoder.preambleBit(prefix)) prefix++;
  }
}

class _Candidate {
  final _Hit hit;
  int next, bitCount = 0, byte = 0, end = 0;
  double confidence = 1;
  final bytes = <int>[];
  String failure = '', detail = '';
  _Candidate(this.hit, int symbol) : next = hit.end + symbol;
}

// D06's bounded observation ring and slot evidence gates are retained. D07
// updates one shift register per timing phase, instead of re-reading 32 slots.
class GridDecoder {
  static const hop = 240, sync = 0xd391a65c;
  static int preambleBit(int position) => (sync >> (31 - position)) & 1;
  final BeaconConfig config;
  final BeaconCodec codec;
  final void Function() onLock;
  final void Function(List<int>, double, int) onFrame;
  final void Function(String) onReject;
  final diagnostics = GridDiagnostics();
  late final int _symbol = config.sampleRate * config.symbolMs ~/ 1000;
  late final int _capacity = (_symbol * 34 / hop).ceil() + 3;
  late final List<double> _zero = List.filled(_capacity, 0);
  late final List<double> _one = List.filled(_capacity, 0);
  late final List<double> _support = List.filled(_capacity, 0);
  late final _phases = [
    for (var p = 0; p < _symbol; p += hop) _Phase(p, _symbol + p),
  ];
  late final _failure = _failureTable();
  final _tested = <int>{};
  final _candidates = <_Candidate>[];
  final _hits = <_Hit>[];
  int _hops = 0, _groupEnd = 0, _ignoreThrough = -1;
  int? _firstSignal, _firstLock, _preferred;
  String _slotReason = '';

  GridDecoder(
    this.config, {
    required this.onLock,
    required this.onFrame,
    required this.onReject,
    BeaconCodec? codec,
  }) : codec = codec ?? ExperimentalCodec();

  List<int> _failureTable() {
    final result = List<int>.filled(32, 0);
    var matched = 0;
    for (var i = 1; i < 32; i++) {
      while (matched > 0 && preambleBit(i) != preambleBit(matched)) {
        matched = result[matched - 1];
      }
      if (preambleBit(i) == preambleBit(matched)) matched++;
      result[i] = matched;
    }
    return result;
  }

  double _at(List<double> values, int sample) {
    final index = sample ~/ hop;
    final fraction = (sample % hop) / hop;
    final value = values[index % _capacity];
    if (fraction == 0) return value;
    return value + fraction * (values[(index + 1) % _capacity] - value);
  }

  _Slot? _slot(int end) {
    diagnostics.slotEvaluations++;
    final start = end - _symbol;
    if (start < max(0, (_hops - _capacity + 1) * hop) || end > _hops * hop) {
      _slotReason = 'required observations no longer buffered';
      return null;
    }
    final support = _at(_support, end) - _at(_support, start);
    if (support + 1e-6 < _symbol * .25) {
      _slotReason =
          'only ${(support * 1000 / config.sampleRate).toStringAsFixed(1)} ms usable evidence';
      return null;
    }
    final zero = _at(_zero, end) - _at(_zero, start);
    final one = _at(_one, end) - _at(_one, start);
    final confidence = max(zero, one) / (zero + one + 1e-12);
    if (confidence < config.confidence) {
      _slotReason =
          'frequency dominance ${confidence.toStringAsFixed(3)} below ${config.confidence}';
      return null;
    }
    final bit = one > zero ? 1 : 0;
    final values = bit == 1 ? _one : _zero;
    final early = _at(values, start + _symbol ~/ 2) - _at(values, start);
    final score = confidence + .01 * early / (max(zero, one) + 1e-12);
    return (bit: bit, confidence: confidence, score: score);
  }

  void add(double zero, double one, bool candidate) {
    final previous = _hops % _capacity;
    _hops++;
    final current = _hops % _capacity;
    final now = _hops * hop;
    _zero[current] = _zero[previous] + (candidate ? zero * hop : 0);
    _one[current] = _one[previous] + (candidate ? one * hop : 0);
    _support[current] = _support[previous] + (candidate ? hop : 0);
    if (candidate) {
      _firstSignal ??= now - hop;
      diagnostics.usableSignalSeen = true;
    }
    diagnostics.observations = min(_hops, _capacity - 1);
    diagnostics.capacity = _capacity - 1;
    final due = _phases.where((p) => p.next <= now).toList();
    // Prefer the most advanced prefix when multiple phase endpoints are due.
    due.sort(
      (a, b) => a.phase == b.phase
          ? 0
          : a.phase == _preferred
          ? -1
          : b.phase == _preferred
          ? 1
          : b.prefix.compareTo(a.prefix),
    );
    for (final phase in due) {
      final end = phase.next;
      phase.next += _symbol;
      diagnostics.offsetEvaluations++;
      _tested.add(phase.phase);
      diagnostics.timingOffsetsTested = _tested.length;
      phase.add(_slot(end), _failure);
      diagnostics.longestUsableRun = max(
        diagnostics.longestUsableRun,
        phase.count,
      );
      if (phase.count < 32) continue;
      diagnostics.searches++;
      var difference = phase.word ^ sync, errors = 0;
      while (difference != 0) {
        difference &= difference - 1;
        errors++;
      }
      final prior = diagnostics.bestHamming;
      if (errors < diagnostics.bestHamming) {
        diagnostics.bestHamming = errors;
        diagnostics.bestPreamble = phase.word.toRadixString(2).padLeft(32, '0');
        diagnostics.bestOffsetMs = phase.phase * 1000 / config.sampleRate;
      }
      if (errors == 0 && end > _ignoreThrough) {
        final hit = (
          end: end,
          phase: phase.phase,
          score: phase.score,
          priorHamming: prior,
        );
        if (!diagnostics.locked) {
          _lock(hit, now);
        } else if (end - _groupEnd < _symbol) {
          _addCandidate(hit);
        } else {
          _hits.add(hit);
        }
      }
    }
    _prioritize();
    _hits.removeWhere(
      (hit) => hit.end <= _ignoreThrough || now - hit.end > 32 * _symbol,
    );
    if (_hits.length > _phases.length * 2) {
      _hits.removeRange(0, _hits.length - _phases.length * 2);
    }
    if (!diagnostics.locked && _hits.isNotEmpty) _lock(_hits.removeAt(0), now);
    if (diagnostics.locked) _decode(now);
  }

  void _prioritize() {
    _Phase? preferred;
    for (final phase in _phases) {
      if (phase.prefix >= 8 &&
          (preferred == null ||
              phase.prefix > preferred.prefix ||
              (phase.prefix == preferred.prefix &&
                  phase.score > preferred.score))) {
        preferred = phase;
      }
    }
    _preferred = preferred?.phase;
    diagnostics.preferredOffsetMs = _preferred == null
        ? null
        : _preferred! * 1000 / config.sampleRate;
  }

  void _lock(_Hit hit, int now) {
    diagnostics.locked = true;
    diagnostics.locks++;
    diagnostics.recoveredPreamble = sync.toRadixString(2).padLeft(32, '0');
    diagnostics.lockedOffsetMs = hit.phase * 1000 / config.sampleRate;
    if (_firstLock == null) {
      _firstLock = now;
      diagnostics.bestHammingBeforeLock = hit.priorHamming;
      diagnostics.signalToLockMs =
          (now - (_firstSignal ?? now)) * 1000 / config.sampleRate;
    }
    _groupEnd = hit.end;
    _candidates.clear();
    _addCandidate(hit);
    // No D06 lookahead deadline: lock and begin frame processing now.
    onLock();
  }

  void _addCandidate(_Hit hit) {
    if (_candidates.any((c) => c.hit.phase == hit.phase)) return;
    _candidates.add(_Candidate(hit, _symbol));
    // Nearby exact alignments are bounded fallbacks; each retains a fixed grid.
    // They do not delay the primary alignment or duplicate a delivered frame.
    _candidates.sort((a, b) => b.hit.score.compareTo(a.hit.score));
  }

  void _decode(int now) {
    for (final candidate in _candidates) {
      while (candidate.failure.isEmpty && candidate.next <= now) {
        final slot = _slot(candidate.next);
        if (slot == null) {
          _fail(
            candidate,
            'missing slot',
            'Data slot ${candidate.bitCount + 1}: $_slotReason',
          );
          break;
        }
        candidate.confidence = min(candidate.confidence, slot.confidence);
        candidate.byte = (candidate.byte << 1) | slot.bit;
        candidate.bitCount++;
        candidate.end = candidate.next;
        candidate.next += _symbol;
        if (candidate.bitCount % 8 != 0) continue;
        candidate.bytes.add(candidate.byte);
        candidate.byte = 0;
        final bytes = candidate.bytes;
        if (bytes.length < 2) continue;
        if (bytes[0] != 1 || bytes[1] < 1 || bytes[1] > 64) {
          _fail(
            candidate,
            'invalid header',
            'Invalid header: version ${bytes[0]}, length ${bytes[1]}',
          );
          break;
        }
        if (bytes.length != bytes[1] + 4) continue;
        final payload = codec.decode(bytes);
        if (payload == null) {
          _fail(
            candidate,
            'CRC/payload failure',
            'CRC or UTF-8 payload validation failed',
          );
          break;
        }
        diagnostics.validFrames++;
        diagnostics.decodedPayload = payload;
        diagnostics.lockedOffsetMs =
            candidate.hit.phase * 1000 / config.sampleRate;
        diagnostics.bestOffsetMs = diagnostics.lockedOffsetMs;
        diagnostics.lockToPayloadMs ??=
            (now - (_firstLock ?? now)) * 1000 / config.sampleRate;
        diagnostics.signalToPayloadMs ??=
            (now - (_firstSignal ?? now)) * 1000 / config.sampleRate;
        onFrame(List.of(bytes), candidate.confidence, candidate.end);
        _ignoreThrough = candidate.end;
        _unlock('frame complete');
        return;
      }
    }
    if (now >= _groupEnd + _symbol &&
        _candidates.every((c) => c.failure.isNotEmpty)) {
      final failure = _candidates.firstWhere(
        (c) => c.failure == 'CRC/payload failure',
        orElse: () => _candidates.first,
      );
      diagnostics.lastFailure = failure.detail;
      if (failure.failure == 'CRC/payload failure') {
        onFrame(List.of(failure.bytes), failure.confidence, failure.end);
      } else {
        if (failure.failure == 'missing slot') diagnostics.missingSlots++;
        onReject(failure.failure);
      }
      _ignoreThrough = _groupEnd + _symbol - 1;
      _unlock(failure.failure);
    }
  }

  void _fail(_Candidate candidate, String reason, String detail) {
    candidate.failure = reason;
    candidate.detail = detail;
    diagnostics.failedCandidates++;
    diagnostics.failureCounts.update(reason, (n) => n + 1, ifAbsent: () => 1);
  }

  void _unlock(String reason) {
    diagnostics.locked = false;
    diagnostics.lastUnlock = reason;
    _candidates.clear();
    // Do not discard accumulated observations, phase registers or later hits.
  }

  void markValidated() {
    diagnostics.totalDetectionMs ??=
        (_hops * hop - (_firstSignal ?? _hops * hop)) *
        1000 /
        config.sampleRate;
  }

  void finishInput() => diagnostics.stopped = true;
}
