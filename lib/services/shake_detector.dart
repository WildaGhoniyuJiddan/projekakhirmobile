import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// Deteksi goyangan (shake) dari accelerometer.
///
/// Testable: stream bisa di-inject; default pakai
/// [accelerometerEventStream].
class ShakeDetector {
  ShakeDetector({
    Stream<AccelerometerEvent>? stream,
    this.threshold = 18.0,
    this.cooldown = const Duration(seconds: 2),
  }) : _stream = stream ?? accelerometerEventStream();

  final Stream<AccelerometerEvent> _stream;
  final double threshold;
  final Duration cooldown;

  StreamSubscription<AccelerometerEvent>? _sub;
  DateTime _lastShake = DateTime.fromMillisecondsSinceEpoch(0);

  /// Mulai mendengarkan; [onShake] dipanggil tiap goyangan terdeteksi.
  void start(void Function() onShake) {
    stop();
    var px = 0.0, py = 0.0, pz = 0.0;
    var first = true;
    _sub = _stream.listen((e) {
      if (first) {
        px = e.x;
        py = e.y;
        pz = e.z;
        first = false;
        return;
      }
      final dx = e.x - px, dy = e.y - py, dz = e.z - pz;
      px = e.x;
      py = e.y;
      pz = e.z;
      final mag = sqrt(dx * dx + dy * dy + dz * dz);
      final now = DateTime.now();
      if (mag > threshold && now.difference(_lastShake) > cooldown) {
        _lastShake = now;
        onShake();
      }
    });
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
