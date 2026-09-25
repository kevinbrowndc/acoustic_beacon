import 'dart:math';
import 'package:acoustic_beacon/protocol/beacon_protocol.dart';

class GridDiagnostics {
  int observations = 0, capacity = 0, searches = 0;
  int bestHamming = 33, locks = 0, missingSlots = 0;
  double? bestOffsetMs, lockedOffsetMs;
  String bestPreamble = '', recoveredPreamble = '', lastUnlock = 'none';
  bool locked = false;
  String get summary =>
      'D06 TIMING GRID (5 ms search resolution)\n'
      'Rolling buffer: $observations/$capacity observations (${observations * 5} ms)\n'
      'Best timing offset: ${bestOffsetMs?.toStringAsFixed(1) ?? "none"} ms\n'
      'Best preamble: ${bestPreamble.isEmpty ? "none" : bestPreamble}\n'
      'Hamming distance: ${bestHamming == 33 ? "no full window" : "$bestHamming/32"}\n'
      'Timing lock achieved: ${locks > 0 ? "YES ($locks)" : "NO"}; now ${locked ? "LOCKED" : "searching"}\n'
      'Last locked offset: ${lockedOffsetMs?.toStringAsFixed(1) ?? "none"} ms\n'
      'Recovered preamble: ${recoveredPreamble.isEmpty ? "none" : recoveredPreamble}\n'
      'Missing slots: $missingSlots; last unlock: $lastUnlock';
}

typedef _Slot = ({int bit, double confidence, double score});

// A bounded prefix-sum ring retains 34 symbols of gated frequency evidence.
// Interpolated endpoints also handle symbol durations not divisible by 5 ms.
class GridDecoder {
  static const hop = 240, sync = 0xd391a65c;
  final BeaconConfig config;
  final void Function() onLock;
  final void Function(List<int>, double, int) onFrame;
  final void Function(String) onReject;
  final diagnostics = GridDiagnostics();
  late final int _symbol = config.sampleRate * config.symbolMs ~/ 1000;
  late final int _capacity = (_symbol * 34 / hop).ceil() + 3;
  late final List<double> _zero = List.filled(_capacity, 0);
  late final List<double> _one = List.filled(_capacity, 0);
  late final List<double> _support = List.filled(_capacity, 0);
  int slotEvaluations =
      0; // Test-only work counter; baseline behavior unchanged.
  int _hops = 0, _deadline = 0, _bestEnd = 0, _next = 0;
  double _bestScore = -1, _frameConfidence = 1;
  final _bits = <int>[];

  GridDecoder(
    this.config, {
    required this.onLock,
    required this.onFrame,
    required this.onReject,
  });

  double _at(List<double> values, int sample) {
    final index = sample ~/ hop;
    final fraction = (sample % hop) / hop;
    final value = values[index % _capacity];
    if (fraction == 0) return value;
    return value + fraction * (values[(index + 1) % _capacity] - value);
  }

  _Slot? _slot(int end) {
    slotEvaluations++;
    final start = end - _symbol;
    if (start < max(0, (_hops - _capacity + 1) * hop) || end > _hops * hop) {
      return null;
    }
    final support = _at(_support, end) - _at(_support, start);
    // Same minimum evidence duration as before, now accumulated across a slot.
    if (support + 1e-6 < _symbol * .25) return null;
    final zero = _at(_zero, end) - _at(_zero, start);
    final one = _at(_one, end) - _at(_one, start);
    final confidence = max(zero, one) / (zero + one + 1e-12);
    if (confidence < config.confidence) return null;
    final bit = one > zero ? 1 : 0;
    final values = bit == 1 ? _one : _zero;
    final early = _at(values, start + _symbol ~/ 2) - _at(values, start);
    // Rank exact matches by purity; first-half energy breaks near ties using
    // the existing transmitted tone/silence shape. This is not an extra gate.
    final score = confidence + .01 * early / (max(zero, one) + 1e-12);
    return (bit: bit, confidence: confidence, score: score);
  }

  void add(double zero, double one, bool candidate) {
    final previous = _hops % _capacity;
    _hops++;
    final current = _hops % _capacity;
    _zero[current] = _zero[previous] + (candidate ? zero * hop : 0);
    _one[current] = _one[previous] + (candidate ? one * hop : 0);
    _support[current] = _support[previous] + (candidate ? hop : 0);
    diagnostics.observations = min(_hops, _capacity - 1);
    diagnostics.capacity = _capacity - 1;
    final now = _hops * hop;
    if (!diagnostics.locked) {
      _search(now);
      if (_deadline > 0 && now >= _deadline) {
        diagnostics.locked = true;
        diagnostics.locks++;
        diagnostics.lockedOffsetMs =
            (_bestEnd % _symbol) * 1000 / config.sampleRate;
        diagnostics.recoveredPreamble = sync.toRadixString(2).padLeft(32, '0');
        _bits.clear();
        _frameConfidence = 1;
        _next = _bestEnd + _symbol;
        _deadline = 0;
        onLock();
      }
    }
    while (diagnostics.locked && _next <= now) {
      final slot = _slot(_next);
      if (slot == null) {
        diagnostics.missingSlots++;
        onReject('missing slot');
        _unlock('missing slot');
        break;
      }
      _frameConfidence = min(_frameConfidence, slot.confidence);
      _bits.add(slot.bit);
      final end = _next;
      _next += _symbol;
      if (_bits.length % 8 != 0) continue;
      final bytes = <int>[];
      for (var i = 0; i < _bits.length; i += 8) {
        var byte = 0;
        for (var j = 0; j < 8; j++) {
          byte = (byte << 1) | _bits[i + j];
        }
        bytes.add(byte);
      }
      if (bytes.length < 2) continue;
      if (bytes[0] != 1 || bytes[1] < 1 || bytes[1] > 64) {
        onReject('invalid header');
        _unlock('invalid header');
      } else if (bytes.length == bytes[1] + 4) {
        onFrame(bytes, _frameConfidence, end);
        _unlock('frame complete');
      }
    }
  }

  void _search(int end) {
    if (end < 32 * _symbol) return;
    diagnostics.searches++;
    var word = 0;
    var score = 0.0;
    for (var i = 31; i >= 0; i--) {
      final slot = _slot(end - i * _symbol);
      if (slot == null) return;
      word = ((word << 1) | slot.bit) & 0xffffffff;
      score += slot.score;
    }
    var difference = word ^ sync, errors = 0;
    while (difference != 0) {
      difference &= difference - 1;
      errors++;
    }
    if (errors < diagnostics.bestHamming) {
      diagnostics.bestHamming = errors;
      diagnostics.bestPreamble = word.toRadixString(2).padLeft(32, '0');
      diagnostics.bestOffsetMs = (end % _symbol) * 1000 / config.sampleRate;
    }
    if (errors != 0) return; // Never lock on an approximate preamble.
    if (_deadline == 0) {
      _deadline = end + _symbol; // Compare all phases around this exact hit.
      _bestScore = -1;
    }
    if (score > _bestScore) {
      _bestScore = score;
      _bestEnd = end;
      diagnostics.bestOffsetMs = (end % _symbol) * 1000 / config.sampleRate;
    }
  }

  void _unlock(String reason) {
    diagnostics.locked = false;
    diagnostics.lastUnlock = reason;
    _bits.clear();
    _deadline = 0;
  }
}
