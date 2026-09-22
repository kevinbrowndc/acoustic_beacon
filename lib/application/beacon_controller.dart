import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio/microphone.dart';
import '../data/content.dart';
import '../dsp/detector.dart';
import '../protocol/beacon_protocol.dart';

enum ListeningState {
  idle,
  requestingPermission,
  listening,
  candidateSignal,
  decoding,
  validBeacon,
  error,
}

class BeaconController extends ChangeNotifier {
  final PcmCapture capture;
  final ContentRepository repository;
  BeaconConfig config = const BeaconConfig();
  late BeaconDetector detector;
  ListeningState state = ListeningState.idle;
  BeaconContent? content;
  DateTime? lastDetection;
  String? error;
  bool active = false, busy = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime _lastUi = DateTime(2000);
  StreamSubscription<List<double>>? _subscription;
  BeaconController(this.capture, this.repository) {
    _buildDetector();
  }
  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  void _buildDetector() {
    detector = BeaconDetector(config, _validated);
  }

  Future<void> _validated(String id, double confidence) async {
    final generation = _generation;
    final now = DateTime.now();
    if (content?.id == id &&
        lastDetection != null &&
        now.difference(lastDetection!).inSeconds < 30) {
      return;
    }
    try {
      final found = await repository.find(id);
      if (generation != _generation || !active) {
        return;
      }
      content =
          found ??
          BeaconContent(
            id,
            'Acoustic Beacon',
            'Beacon Detected',
            'This validated beacon has no registered content yet.',
          );
      lastDetection = now;
      state = ListeningState.validBeacon;
      notifyListeners();
    } catch (e) {
      if (generation == _generation) {
        error = 'Content could not be loaded. Please try again.';
        notifyListeners();
      }
    }
  }

  Future<void> start() async {
    if (busy || active || _disposed) {
      return;
    }
    busy = true;
    final generation = ++_generation;
    error = null;
    state = ListeningState.requestingPermission;
    notifyListeners();
    _buildDetector();
    try {
      final stream = await capture.start();
      if (generation != _generation) {
        await capture.stop();
        return;
      }
      active = true;
      state = ListeningState.listening;
      _subscription = stream.listen(
        (samples) {
          detector.add(samples);
          if (content == null) {
            state = detector.diagnostics.preamble
                ? ListeningState.decoding
                : detector.diagnostics.candidate
                ? ListeningState.candidateSignal
                : ListeningState.listening;
          }
          if (DateTime.now().difference(_lastUi).inMilliseconds >= 150) {
            _lastUi = DateTime.now();
            notifyListeners();
          }
        },
        onError: (Object e) {
          unawaited(_failed(e));
        },
        onDone: () {
          if (active) {
            unawaited(
              _failed(
                StateError('Microphone stream ended. Try listening again.'),
              ),
            );
          }
        },
      );
    } catch (e) {
      active = false;
      try {
        await capture.stop();
      } catch (_) {
        /* Preserve the original failure. */
      }
      error = e.toString();
      state = ListeningState.error;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _failed(Object e) async {
    await stop();
    error = e.toString();
    state = ListeningState.error;
    notifyListeners();
  }

  Future<void> stop() async {
    ++_generation;
    if (!active && !busy && _subscription == null) {
      return;
    }
    active = false;
    await _subscription?.cancel();
    _subscription = null;
    try {
      await capture.stop();
      state = ListeningState.idle;
    } catch (e) {
      error = 'Could not stop microphone: $e';
      state = ListeningState.error;
    }
    notifyListeners();
  }

  Future<void> configure(BeaconConfig next) async {
    next.validate();
    await stop();
    config = next;
    _buildDetector();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    active = false;
    _subscription?.cancel();
    capture.dispose();
    super.dispose();
  }
}
