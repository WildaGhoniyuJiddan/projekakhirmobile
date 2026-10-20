import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Kartu 3D yang miring mengikuti gyroscope (maks ±[maxTilt] radian).
///
/// [rotationStream] bisa di-inject untuk testing; default memakai
/// [gyroscopeEventStream]. Di perangkat tanpa sensor, kartu diam.
class TiltCard extends StatefulWidget {
  const TiltCard({
    super.key,
    required this.child,
    this.rotationStream,
    this.maxTilt = 0.25,
    this.enabled = true,
  });

  final Widget child;
  final Stream<GyroscopeEvent>? rotationStream;
  final double maxTilt;

  /// Bila false, kartu diam (pengaturan user).
  final bool enabled;

  @override
  State<TiltCard> createState() => _TiltCardState();
}

class _TiltCardState extends State<TiltCard> {
  StreamSubscription<GyroscopeEvent>? _sub;
  double _rx = 0, _ry = 0;

  @override
  void initState() {
    super.initState();
    _sub = (widget.rotationStream ?? gyroscopeEventStream()).listen(
      (e) {
        // Integrasi sederhana kecepatan sudut → sudut, dengan decay.
        setState(() {
          _ry = (_ry + e.y * 0.05).clamp(-widget.maxTilt, widget.maxTilt);
          _rx = (_rx + e.x * 0.05).clamp(-widget.maxTilt, widget.maxTilt);
          _rx *= 0.95;
          _ry *= 0.95;
        });
      },
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || (_rx == 0 && _ry == 0)) {
      return widget.child;
    }
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..rotateX(_rx)
        ..rotateY(-_ry),
      child: widget.child,
    );
  }
}
