// D05: observational metadata only. Never used to make decoder decisions.
class BurstTrace {
  final int number,
      timeMs,
      bit,
      toneMs,
      spanMs,
      gapMs,
      zeros,
      ones,
      transitions;
  final String run, status, phase, before, after;
  final String boundary;
  const BurstTrace({
    required this.number,
    required this.timeMs,
    required this.bit,
    required this.toneMs,
    required this.spanMs,
    required this.gapMs,
    required this.zeros,
    required this.ones,
    required this.transitions,
    required this.run,
    required this.status,
    required this.phase,
    required this.before,
    required this.after,
    this.boundary = 'quiet',
  });
  String compact(double zeroHz, double oneHz) =>
      '#$number ${bit == 0 ? zeroHz.toInt() : oneHz.toInt()} b$bit '
      'T$toneMs G$gapMs $status/$boundary';
  String detail(double zeroHz, double oneHz) =>
      '${compact(zeroHz, oneHz)}\n'
      't=$timeMs span=$spanMs ms; votes 0:$zeros 1:$ones flips:$transitions\n'
      '$phase $before > $after\nCandidate 5ms bins: $run${zeros + ones > run.length ? "…" : ""}';
}

class ReceiverTrace {
  static const expected = '11010011100100011010011001011100';
  final first = <BurstTrace>[];
  final recent = <BurstTrace>[];
  List<BurstTrace> bestBursts = [];
  bool _newBest = false;
  int bestAt = 0;
  int totalBursts = 0, comparisons = 0, resets = 0, syncBits = 0;
  String rolling = '', lastCompared = '', best = '', lastReset = 'none';
  int bestErrors = 33;
  String openBurst = 'none';
  final resetReasons = <String, int>{};

  void record(BurstTrace row) {
    totalBursts++;
    if (first.length < 64) first.add(row);
    recent.add(row);
    if (recent.length > 128) recent.removeAt(0);
    if (_newBest) {
      bestAt = row.number;
      bestBursts = recent
          .skip(recent.length > 64 ? recent.length - 64 : 0)
          .toList();
      _newBest = false;
    }
  }

  void compare(int bit, int sync) {
    comparisons++;
    if (syncBits < 32) syncBits++;
    rolling = sync.toRadixString(2).padLeft(32, '0').substring(32 - syncBits);
    lastCompared = rolling;
    // Compare only complete windows; do not mistake zero padding for received bits.
    if (syncBits == 32) {
      var errors = 0;
      for (var i = 0; i < 32; i++) {
        if (rolling[i] != expected[i]) errors++;
      }
      if (errors < bestErrors) {
        bestErrors = errors;
        best = rolling;
        _newBest = true;
      }
    }
  }

  void reset(String reason) {
    // The decoder calls idle reset every quiet hop. Record meaningful resets once.
    if (rolling.isNotEmpty) {
      resets++;
      lastReset = reason;
      resetReasons.update(reason, (n) => n + 1, ifAbsent: () => 1);
    }
    rolling = '';
    syncBits = 0;
  }

  String grouped(String bits) => bits.isEmpty
      ? 'none'
      : [
          for (var i = 0; i < bits.length; i += 8)
            bits.substring(i, i + 8 < bits.length ? i + 8 : bits.length),
        ].join(' ');

  String summary(double zeroHz, double oneHz) =>
      'D05 PHOTO SUMMARY (retained after Stop)\n'
      '0=${zeroHz.toInt()} Hz  1=${oneHz.toInt()} Hz\n'
      'Expected: ${grouped(expected)}\n'
      'Last comparison: ${grouped(lastCompared)}\n'
      'Closest full 32 (#$bestAt): ${grouped(best)}\n'
      'Bit differences: ${best.isEmpty ? "no full window" : "$bestErrors/32"}\n'
      'Comparisons $comparisons; resets $resets ($lastReset)\n'
      'Reset counts: $resetReasons\n'
      'Open burst: $openBurst\n'
      'T=tone ms, G=quiet ms BEFORE burst\n'
      'First 12 bursts (preserved):\n'
      '${first.take(12).map((r) => r.compact(zeroHz, oneHz)).join("\n")}';

  String details(double zeroHz, double oneHz) =>
      'Bounded log: first 64 and last 128 of $totalBursts bursts.\n'
      'Times use audio samples; T counts candidate blocks; span includes internal gaps.\n'
      'G is preceding noncandidate gap, not necessarily acoustic silence.\n'
      'ACCEPT/SHORT/LONG describe D05 burst parsing only; they do not control the D06 grid.\n'
      'SYNC rows show actual rolling comparison before > after. DATA rows are payload bits.\n\n'
      'CLOSEST PREAMBLE CONTEXT\n${bestBursts.map((r) => r.detail(zeroHz, oneHz)).join("\n\n")}\n\n'
      'FIRST BURSTS\n${first.map((r) => r.detail(zeroHz, oneHz)).join("\n\n")}\n\n'
      'LATEST BURSTS\n${recent.map((r) => r.detail(zeroHz, oneHz)).join("\n\n")}';
}
