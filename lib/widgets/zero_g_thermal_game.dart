import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Game status state for Zero-G Thermal Protocol.
enum GameStatus {
  ready,
  playing,
  won,
  shortCircuit,
  thermalThrottle,
}

/// Standalone, fully procedural 2D retro pixel-art physics minigame.
///
/// Features:
/// - Target: Android portrait orientation (locked via SystemChrome).
/// - Procedural Pixel Art: NO external assets (.png/.jpg). Every element
///   (motherboard PCB, gold pins, CPU IHS, thermal paste, warning banners,
///   pixel numbers) is drawn via [CustomPainter] and [canvas.drawRect].
/// - 60 FPS Ticker loop with SingleTickerProviderStateMixin.
/// - Tilt control via [accelerometerEventStream] from sensors_plus, with
///   touch/drag fallback for emulators.
/// - Fluid motion with viscous resistance and random Zero-G repulsive pulses.
/// - 20x20 boolean coverage grid (Win: >= 85% in 30s).
/// - Hazard boundary: touching outer LGA pins triggers short circuit.
class ZeroGThermalGame extends StatefulWidget {
  final void Function(bool isWin, int coverageScore) onGameFinished;

  const ZeroGThermalGame({
    super.key,
    required this.onGameFinished,
  });

  @override
  State<ZeroGThermalGame> createState() => _ZeroGThermalGameState();
}

class _ZeroGThermalGameState extends State<ZeroGThermalGame>
    with SingleTickerProviderStateMixin {
  // Game Loop
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  // Sensor Subscription & Tilt Physics
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  double _rawSensorX = 0.0;
  double _rawSensorY = 0.0;
  double _neutralTiltX = 0.0;
  double _neutralTiltY = 0.0; // Dynamic neutral calibrated automatically on start
  double _filteredTiltX = 0.0;
  double _filteredTiltY = 0.0;
  double _touchVirtualTiltX = 0.0;
  double _touchVirtualTiltY = 0.0;
  bool _isUsingTouch = false;

  // Speed & Viscosity Sensitivity Mode (Default: NORMAL / 1.2x for fast, responsive gyro tilt)
  int _speedIndex = 1;
  static const List<double> _speedMultipliers = [0.8, 1.2, 1.6];
  static const List<String> _speedLabels = ['HALUS', 'NORMAL', 'RESPONSIF'];

  double get _speedMultiplier => _speedMultipliers[_speedIndex];
  String get _speedLabel => _speedLabels[_speedIndex];

  // Game Dimensions & Layout (set in tick based on canvas/box size)
  double _ihsSize = 210.0;
  double _socketSize = 276.0;
  final int _gridResolution = 20;

  // 20x20 Coverage Grid
  late List<List<bool>> _coverageGrid;
  int _coveredCells = 0;
  int _coveragePercentage = 0;

  // Player Entity (Thermal Paste Blob)
  Offset _pastePos = Offset.zero; // relative to IHS center
  Offset _pasteVel = Offset.zero;
  final double _pasteRadius = 14.0;

  // Time & Temperature
  double _timeRemaining = 30.0;
  int _cpuTemp = 40; // 40°C -> 100°C

  // Anti-Gravity Pulse Mechanics
  final Random _rng = Random(42);
  double _pulseCountdown = 5.5; // Next pulse in 5-7s
  double _pulseDuration = 0.0; // 1.5s when active
  bool _isPulseActive = false;
  double _pulseWarningBlink = 0.0;
  double _lastHapticTick = 0.0;

  // Sparks & Particle effects
  final List<PixelSpark> _sparks = [];

  // Game State
  GameStatus _status = GameStatus.ready;
  bool _hasCallbackFired = false;

  @override
  void initState() {
    super.initState();
    _lockOrientationToPortrait();
    _resetGrid();
    _startSensorListener();
    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  @override
  void dispose() {
    _restoreOrientations();
    _accelSubscription?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _lockOrientationToPortrait() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  void _restoreOrientations() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _resetGrid() {
    _coverageGrid = List.generate(
      _gridResolution,
      (_) => List<bool>.filled(_gridResolution, false),
    );
    _coveredCells = 0;
    _coveragePercentage = 0;
    _pastePos = Offset.zero;
    _pasteVel = Offset.zero;
    _timeRemaining = 30.0;
    _cpuTemp = 40;
    _pulseCountdown = 5.0 + _rng.nextDouble() * 2.0;
    _pulseDuration = 0.0;
    _isPulseActive = false;
    _sparks.clear();
    _hasCallbackFired = false;
  }

  void _startSensorListener() {
    try {
      _accelSubscription = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen(
        (AccelerometerEvent event) {
          _rawSensorX = event.x;
          _rawSensorY = event.y;
        },
        onError: (_) {
          // Accelerometer not available (e.g. desktop/emulator/testing)
        },
      );
    } catch (_) {
      // Graceful fallback for non-sensor environments
    }
  }

  void _calibrateTilt() {
    _neutralTiltX = _rawSensorX;
    _neutralTiltY = _rawSensorY;
    HapticFeedback.lightImpact();
  }

  void _cycleSpeedMode() {
    setState(() {
      _speedIndex = (_speedIndex + 1) % _speedMultipliers.length;
    });
    HapticFeedback.lightImpact();
  }

  void _startGame() {
    setState(() {
      _resetGrid();
      // Auto-calibrate neutral holding angle at moment of start
      _neutralTiltX = _rawSensorX;
      _neutralTiltY = _rawSensorY;
      _status = GameStatus.playing;
    });
    HapticFeedback.lightImpact();
  }

  void _restartGame() {
    setState(() {
      _resetGrid();
      // Auto-calibrate neutral holding angle on restart
      _neutralTiltX = _rawSensorX;
      _neutralTiltY = _rawSensorY;
      _status = GameStatus.playing;
    });
    HapticFeedback.lightImpact();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    if (_lastElapsed == Duration.zero) {
      _lastElapsed = elapsed;
      return;
    }

    final double dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    // Guard against large lag spikes
    final double clampedDt = dt.clamp(0.001, 0.045);

    if (_status == GameStatus.playing) {
      _updatePhysics(clampedDt);
      _updateTimerAndTemp(clampedDt);
      _updateAntiGravityPulses(clampedDt);
      _updateSparks(clampedDt);
      _checkGameConditions();
    } else {
      _updateSparks(clampedDt);
    }

    // Trigger procedural frame repaint
    setState(() {});
  }

  void _updatePhysics(double dt) {
    // 1. Process Tilt Sensor
    // Android portrait mapping (marble-on-tray physics):
    // - Tilting right edge DOWN gives negative sensor.x -> move right (+X in screen coordinates)
    // - Tilting left edge DOWN gives positive sensor.x -> move left (-X in screen coordinates)
    // - Tilting top edge DOWN gives lower sensor.y -> move top (-Y in screen coordinates)
    // - Tilting bottom edge DOWN gives higher sensor.y -> move bottom (+Y in screen coordinates)
    double rawTiltX = -(_rawSensorX - _neutralTiltX);
    double rawTiltY = (_rawSensorY - _neutralTiltY);

    if (_isUsingTouch) {
      rawTiltX = _touchVirtualTiltX;
      rawTiltY = _touchVirtualTiltY;
    }

    // Gentle deadzone (0.12 m/s²) - filters jitter without deadening response
    const double deadzone = 0.12;
    double targetTiltX = 0.0;
    if (rawTiltX.abs() > deadzone) {
      targetTiltX = rawTiltX.sign * (rawTiltX.abs() - deadzone);
    }
    double targetTiltY = 0.0;
    if (rawTiltY.abs() > deadzone) {
      targetTiltY = rawTiltY.sign * (rawTiltY.abs() - deadzone);
    }

    // Clamp effective tilt angle to ±3.0 m/s² (~18° tilt is already 100% full tilt!)
    // The player NEVER needs to rotate the phone 90° or 180°!
    targetTiltX = targetTiltX.clamp(-3.0, 3.0);
    targetTiltY = targetTiltY.clamp(-3.0, 3.0);

    // Fast, crisp low-pass filter (0.35 / 0.65) for instant wrist-tilt reaction
    _filteredTiltX = _filteredTiltX * 0.35 + targetTiltX * 0.65;
    _filteredTiltY = _filteredTiltY * 0.35 + targetTiltY * 0.65;

    // High tilt sensitivity: small wrist flick gives immediate steering
    final double tiltSensitivity = 170.0 * _speedMultiplier;
    Offset accel = Offset(
      _filteredTiltX * tiltSensitivity,
      _filteredTiltY * tiltSensitivity,
    );

    // Active Counter-Steering Brake:
    // When tilting opposite to current movement direction, apply 2.4x braking force
    // to instantly stop and reverse momentum on a dime!
    if (accel.dx * _pasteVel.dx < 0) {
      accel = Offset(accel.dx * 2.4, accel.dy);
    }
    if (accel.dy * _pasteVel.dy < 0) {
      accel = Offset(accel.dx, accel.dy * 2.4);
    }

    // 2. Anti-Gravity Pulse Repulsive Vector
    if (_isPulseActive) {
      // Repel outward away from the center of the IHS plate
      Offset fromCenter = _pastePos;
      double dist = fromCenter.distance;
      Offset outwardDir;
      if (dist < 2.0) {
        final double randomAngle = _rng.nextDouble() * 2 * pi;
        outwardDir = Offset(cos(randomAngle), sin(randomAngle));
      } else {
        outwardDir = fromCenter / dist;
      }

      // Controlled repulsive pulse so player can counter-steer comfortably
      final double pulseRepulsionForce = 140.0 * _speedMultiplier;
      accel += outwardDir * pulseRepulsionForce;
    }

    // 3. Integrate Velocity & Viscous Fluid Resistance (Drag)
    _pasteVel += accel * dt;

    // Viscous fluid damping (pow(0.04, dt) allows agile steering and quick stops)
    final double dragFactor = pow(0.04, dt).toDouble();
    _pasteVel *= dragFactor;

    // Terminal velocity clamp: 145.0 dp/s
    final double maxSpeed = 145.0 * _speedMultiplier;
    if (_pasteVel.distance > maxSpeed) {
      _pasteVel = (_pasteVel / _pasteVel.distance) * maxSpeed;
    }

    // 4. Update Position
    _pastePos += _pasteVel * dt;

    // 5. Update Coverage Trail on 20x20 Grid
    _markCoverageTrail();
  }

  void _markCoverageTrail() {
    final double halfIhs = _ihsSize / 2.0;
    final double cellSize = _ihsSize / _gridResolution;

    // Local coordinates on IHS from 0 to _ihsSize
    final double localX = _pastePos.dx + halfIhs;
    final double localY = _pastePos.dy + halfIhs;

    // Bounding grid range under the fluid blob footprint
    final int minC = ((localX - _pasteRadius) / cellSize).floor().clamp(0, _gridResolution - 1);
    final int maxC = ((localX + _pasteRadius) / cellSize).floor().clamp(0, _gridResolution - 1);
    final int minR = ((localY - _pasteRadius) / cellSize).floor().clamp(0, _gridResolution - 1);
    final int maxR = ((localY + _pasteRadius) / cellSize).floor().clamp(0, _gridResolution - 1);

    for (int r = minR; r <= maxR; r++) {
      for (int c = minC; c <= maxC; c++) {
        if (!_coverageGrid[r][c]) {
          final double cellCenterX = (c + 0.5) * cellSize;
          final double cellCenterY = (r + 0.5) * cellSize;
          final double dx = cellCenterX - localX;
          final double dy = cellCenterY - localY;
          if (dx * dx + dy * dy <= (_pasteRadius * 1.1) * (_pasteRadius * 1.1)) {
            _coverageGrid[r][c] = true;
            _coveredCells++;
          }
        }
      }
    }

    final int totalCells = _gridResolution * _gridResolution;
    _coveragePercentage = ((_coveredCells / totalCells) * 100).clamp(0, 100).toInt();
  }

  void _updateTimerAndTemp(double dt) {
    _timeRemaining = max(0.0, _timeRemaining - dt);

    // Temperature scales from 40°C to 100°C as time runs down
    final double progress = (30.0 - _timeRemaining) / 30.0;
    _cpuTemp = 40 + (progress * 60.0).round().clamp(0, 60);
  }

  void _updateAntiGravityPulses(double dt) {
    if (_isPulseActive) {
      _pulseDuration -= dt;
      _pulseWarningBlink += dt * 8.0;

      // Periodic light haptic pulse during anti-gravity rupture
      if (_timeRemaining - _lastHapticTick > 0.35) {
        _lastHapticTick = _timeRemaining;
        HapticFeedback.lightImpact();
      }

      if (_pulseDuration <= 0.0) {
        _isPulseActive = false;
        _pulseCountdown = 5.0 + _rng.nextDouble() * 2.0;
      }
    } else {
      _pulseCountdown -= dt;
      if (_pulseCountdown <= 0.0) {
        _isPulseActive = true;
        _pulseDuration = 1.5;
        _pulseWarningBlink = 0.0;
        HapticFeedback.heavyImpact();
      }
    }
  }

  void _updateSparks(double dt) {
    for (int i = _sparks.length - 1; i >= 0; i--) {
      final spark = _sparks[i];
      spark.pos += spark.vel * dt;
      spark.life -= dt;
      if (spark.life <= 0) {
        _sparks.removeAt(i);
      }
    }
  }

  void _checkGameConditions() {
    final double halfIhs = _ihsSize / 2.0;

    // 1. FAIL: Short Circuit (Touching outer gold pins beyond the IHS boundary)
    if (_pastePos.dx - _pasteRadius <= -halfIhs ||
        _pastePos.dx + _pasteRadius >= halfIhs ||
        _pastePos.dy - _pasteRadius <= -halfIhs ||
        _pastePos.dy + _pasteRadius >= halfIhs) {
      _triggerFailShortCircuit();
      return;
    }

    // 2. WIN: Coverage >= 85%
    if (_coveragePercentage >= 85) {
      _triggerWin();
      return;
    }

    // 3. FAIL: Thermal Throttle (Timer runs out before 85% coverage)
    if (_timeRemaining <= 0.0) {
      _triggerFailThermalThrottle();
      return;
    }
  }

  void _triggerWin() {
    _status = GameStatus.won;
    HapticFeedback.heavyImpact();
    if (!_hasCallbackFired) {
      _hasCallbackFired = true;
      widget.onGameFinished(true, _coveragePercentage);
    }
  }

  void _triggerFailShortCircuit() {
    _status = GameStatus.shortCircuit;
    HapticFeedback.heavyImpact();

    // Spawn dramatic short-circuit electric pixel sparks
    for (int i = 0; i < 24; i++) {
      final double angle = _rng.nextDouble() * 2 * pi;
      final double speed = 50.0 + _rng.nextDouble() * 120.0;
      _sparks.add(PixelSpark(
        pos: _pastePos,
        vel: Offset(cos(angle) * speed, sin(angle) * speed),
        life: 0.4 + _rng.nextDouble() * 0.4,
        color: i.isEven ? const Color(0xFF60A5FA) : const Color(0xFFFDE047),
      ));
    }

    if (!_hasCallbackFired) {
      _hasCallbackFired = true;
      widget.onGameFinished(false, _coveragePercentage);
    }
  }

  void _triggerFailThermalThrottle() {
    _status = GameStatus.thermalThrottle;
    HapticFeedback.heavyImpact();

    // Spawn thermal smoke/heat pixel sparks
    for (int i = 0; i < 20; i++) {
      final double angle = -pi / 2 + (_rng.nextDouble() - 0.5);
      final double speed = 30.0 + _rng.nextDouble() * 60.0;
      _sparks.add(PixelSpark(
        pos: _pastePos + Offset((_rng.nextDouble() - 0.5) * 20, (_rng.nextDouble() - 0.5) * 20),
        vel: Offset(cos(angle) * speed, sin(angle) * speed),
        life: 0.5 + _rng.nextDouble() * 0.5,
        color: i.isEven ? const Color(0xFFEF4444) : const Color(0xFF78716C),
      ));
    }

    if (!_hasCallbackFired) {
      _hasCallbackFired = true;
      widget.onGameFinished(false, _coveragePercentage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Adapt game dimensions dynamically to portrait screen size
        final double maxBoardWidth = min(constraints.maxWidth, 420.0);
        _socketSize = (maxBoardWidth * 0.74).clamp(240.0, 300.0);
        _ihsSize = _socketSize * 0.75; // e.g. 210 dp

        return Container(
          color: const Color(0xFF09120C), // Dark motherboard solder mask
          child: Stack(
            children: [
              // 1. Procedural CustomPainter Surface with Touch Steering Fallback
              Positioned.fill(
                child: GestureDetector(
                  onPanDown: (details) {
                    _isUsingTouch = true;
                  },
                  onPanUpdate: (details) {
                    // Finger drag acts as responsive virtual tilt on emulators
                    _isUsingTouch = true;
                    _touchVirtualTiltX = (details.delta.dx * 0.35).clamp(-3.0, 3.0);
                    _touchVirtualTiltY = (details.delta.dy * 0.35).clamp(-3.0, 3.0);
                  },
                  onPanEnd: (_) {
                    _isUsingTouch = false;
                    _touchVirtualTiltX = 0.0;
                    _touchVirtualTiltY = 0.0;
                  },
                  onPanCancel: () {
                    _isUsingTouch = false;
                    _touchVirtualTiltX = 0.0;
                    _touchVirtualTiltY = 0.0;
                  },
                  child: CustomPaint(
                    painter: ZeroGThermalPainter(
                      ihsSize: _ihsSize,
                      socketSize: _socketSize,
                      pastePos: _pastePos,
                      pasteRadius: _pasteRadius,
                      coverageGrid: _coverageGrid,
                      gridResolution: _gridResolution,
                      cpuTemp: _cpuTemp,
                      coveragePercentage: _coveragePercentage,
                      timeRemaining: _timeRemaining,
                      isPulseActive: _isPulseActive,
                      pulseWarningBlink: _pulseWarningBlink,
                      tiltX: _filteredTiltX,
                      tiltY: _filteredTiltY,
                      sparks: _sparks,
                      status: _status,
                    ),
                  ),
                ),
              ),

              // 2. In-Game Calibrate & Tilt Helper Bar (Bottom)
              if (_status == GameStatus.playing)
                Positioned(
                  bottom: 12,
                  left: 14,
                  right: 14,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Zero-G Sensor Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141F17),
                          border: Border.all(color: const Color(0xFF22C55E), width: 1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.screen_rotation_rounded, size: 13, color: Color(0xFF4ADE80)),
                            const SizedBox(width: 4),
                            Text(
                              _isUsingTouch ? 'SENTUH' : 'SENSOR',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4ADE80),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Speed Sensitivity Mode Toggle
                      InkWell(
                        onTap: _cycleSpeedMode,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            border: Border.all(color: const Color(0xFF38BDF8), width: 1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.speed_rounded, size: 13, color: Color(0xFF38BDF8)),
                              const SizedBox(width: 4),
                              Text(
                                _speedLabel,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF38BDF8),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Tilt Calibration Button
                      InkWell(
                        onTap: _calibrateTilt,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F2937),
                            border: Border.all(color: const Color(0xFF94A3B8), width: 1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune_rounded, size: 13, color: Color(0xFFE2E8F0)),
                              SizedBox(width: 4),
                              Text(
                                'KALIBRASI',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFE2E8F0),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 3. Ready / Start Overlay
              if (_status == GameStatus.ready)
                _buildStartModal(context),

              // 4. Game Result Modal (Win / Short Circuit / Throttle)
              if (_status == GameStatus.won ||
                  _status == GameStatus.shortCircuit ||
                  _status == GameStatus.thermalThrottle)
                _buildGameOverModal(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStartModal(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1A13),
          border: Border.all(color: const Color(0xFF10B981), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'PROTOKOL TERMAL ZERO-G',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Color(0xFF34D399),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'PROTOKOL IHS ZERO-GRAVITY LGA-1700',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: Color(0xFF9CA3AF),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF16251C),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BriefingRow(
                    icon: Icons.screen_rotation,
                    color: Color(0xFF60A5FA),
                    text: 'MIRINGKAN HP untuk mengarahkan gumpalan thermal paste.',
                  ),
                  SizedBox(height: 8),
                  _BriefingRow(
                    icon: Icons.shield,
                    color: Color(0xFF34D399),
                    text: 'LENGKAPI >= 85% area IHS perak sebelum waktu 30 detik habis.',
                  ),
                  SizedBox(height: 8),
                  _BriefingRow(
                    icon: Icons.warning_amber_rounded,
                    color: Color(0xFFEF4444),
                    text: 'HINDARI pin emas LGA luar (bisa korsleting fatal seketika!).',
                  ),
                  SizedBox(height: 8),
                  _BriefingRow(
                    icon: Icons.waves,
                    color: Color(0xFFFBBF24),
                    text: 'TAHAN dorongan pulsa Anti-Gravitasi yang mendorong keluar.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: const Color(0xFF062313),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: const BeveledRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
                elevation: 4,
              ),
              onPressed: _startGame,
              child: const Text(
                'MULAI PROTOKOL',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverModal(BuildContext context) {
    final bool isWin = _status == GameStatus.won;
    final bool isShort = _status == GameStatus.shortCircuit;

    final Color accentColor = isWin
        ? const Color(0xFF10B981)
        : (isShort ? const Color(0xFF38BDF8) : const Color(0xFFEF4444));

    final String title = isWin
        ? 'PROTOKOL BERHASIL!'
        : (isShort ? 'KORSLETING LISTRIK!' : 'OVERHEAT THROTTLE!');

    final String reason = isWin
        ? 'IHS CPU terlapisi thermal paste secara optimal. Keseimbangan suhu tercapai!'
        : (isShort
            ? 'Thermal paste mengenai pin emas LGA luar, menyebabkan korsleting fatal pada motherboard!'
            : 'Waktu habis! CPU mencapai 100°C sebelum lapisan thermal paste merata.');

    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1A13),
          border: Border.all(color: accentColor, width: 2),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.3),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: accentColor,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFF16251C),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'CAKUPAN',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_coveragePercentage% / 85%',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _coveragePercentage >= 85
                              ? const Color(0xFF34D399)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 28, color: const Color(0xFF374151)),
                  Column(
                    children: [
                      const Text(
                        'SUHU AKHIR',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_cpuTemp°C',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: _cpuTemp >= 90
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF34D399),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Color(0xFFD1D5DB),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: const Color(0xFF062313),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: const BeveledRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                  onPressed: _restartGame,
                  child: const Text(
                    'COBA LAGI',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BriefingRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _BriefingRow({
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              color: Color(0xFFE5E7EB),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class PixelSpark {
  Offset pos;
  Offset vel;
  double life;
  final Color color;

  PixelSpark({
    required this.pos,
    required this.vel,
    required this.life,
    required this.color,
  });
}

// ============================================================================
// PROCEDURAL PIXEL ART RENDERER & CUSTOM PAINTER
// ============================================================================

/// High-performance procedural pixel-art helper.
/// All graphics are drawn strictly via crisp, un-antialiased retro squares
/// using [canvas.drawRect] and pixel matrices.
class PixelArtRenderer {
  static final Paint _paint = Paint()
    ..isAntiAlias = false
    ..style = PaintingStyle.fill;

  /// Draws a single crisp retro square pixel.
  static void drawPixel(Canvas canvas, double x, double y, double size, Color color) {
    _paint.color = color;
    canvas.drawRect(Rect.fromLTWH(x, y, size, size), _paint);
  }

  /// Draws a rectangular region snapped to crisp pixel edges.
  static void drawRect(Canvas canvas, Rect rect, Color color) {
    _paint.color = color;
    canvas.drawRect(rect, _paint);
  }

  /// Draws a multi-colored procedural pixel matrix from string rows.
  static void drawPixelMatrix(
    Canvas canvas,
    double startX,
    double startY,
    double pixelSize,
    List<String> matrix,
    Map<String, Color> palette,
  ) {
    for (int r = 0; r < matrix.length; r++) {
      final String row = matrix[r];
      for (int c = 0; c < row.length; c++) {
        final String char = row[c];
        final Color? color = palette[char];
        if (color != null && color.a > 0) {
          _paint.color = color;
          canvas.drawRect(
            Rect.fromLTWH(
              startX + c * pixelSize,
              startY + r * pixelSize,
              pixelSize,
              pixelSize,
            ),
            _paint,
          );
        }
      }
    }
  }

  // --------------------------------------------------------------------------
  // PROCEDURAL 3x5 RETRO PIXEL FONT (Digits, Letters, Symbols)
  // --------------------------------------------------------------------------
  static const Map<String, List<String>> _font3x5 = {
    '0': ["111", "101", "101", "101", "111"],
    '1': ["010", "110", "010", "010", "111"],
    '2': ["111", "001", "111", "100", "111"],
    '3': ["111", "001", "111", "001", "111"],
    '4': ["101", "101", "111", "001", "001"],
    '5': ["111", "100", "111", "001", "111"],
    '6': ["111", "100", "111", "101", "111"],
    '7': ["111", "001", "010", "010", "010"],
    '8': ["111", "101", "111", "101", "111"],
    '9': ["111", "101", "111", "001", "111"],
    'A': ["010", "101", "111", "101", "101"],
    'B': ["110", "101", "110", "101", "110"],
    'C': ["111", "100", "100", "100", "111"],
    'D': ["110", "101", "101", "101", "110"],
    'E': ["111", "100", "110", "100", "111"],
    'F': ["111", "100", "110", "100", "100"],
    'G': ["111", "100", "101", "101", "111"],
    'H': ["101", "101", "111", "101", "101"],
    'I': ["111", "010", "010", "010", "111"],
    'J': ["001", "001", "001", "101", "010"],
    'K': ["101", "110", "100", "110", "101"],
    'L': ["100", "100", "100", "100", "111"],
    'M': ["101", "111", "101", "101", "101"],
    'N': ["110", "101", "101", "101", "101"],
    'O': ["111", "101", "101", "101", "111"],
    'P': ["111", "101", "111", "100", "100"],
    'Q': ["111", "101", "101", "111", "001"],
    'R': ["110", "101", "110", "101", "101"],
    'S': ["111", "100", "111", "001", "111"],
    'T': ["111", "010", "010", "010", "010"],
    'U': ["101", "101", "101", "101", "111"],
    'V': ["101", "101", "101", "101", "010"],
    'W': ["101", "101", "101", "111", "101"],
    'X': ["101", "101", "010", "101", "101"],
    'Y': ["101", "101", "010", "010", "010"],
    'Z': ["111", "001", "010", "100", "111"],
    ' ': ["000", "000", "000", "000", "000"],
    ':': ["0", "1", "0", "1", "0"],
    '%': ["101", "001", "010", "100", "101"],
    '°': ["11", "11", "00", "00", "00"],
    '-': ["000", "000", "111", "000", "000"],
    '/': ["001", "001", "010", "100", "100"],
    '!': ["1", "1", "1", "0", "1"],
    '.': ["0", "0", "0", "0", "1"],
    '▲': ["010", "111", "111", "000", "000"],
  };

  /// Draws procedural retro text using crisp pixel rectangles.
  static void drawText(
    Canvas canvas,
    String text,
    double startX,
    double startY,
    double pixelSize,
    Color color, {
    double charSpacing = 1.0,
  }) {
    _paint.color = color;
    double cursorX = startX;
    final String upper = text.toUpperCase();

    for (int i = 0; i < upper.length; i++) {
      final String char = upper[i];
      final List<String>? glyph = _font3x5[char];
      if (glyph != null) {
        final int charWidth = glyph[0].length;
        for (int r = 0; r < glyph.length; r++) {
          final String line = glyph[r];
          for (int c = 0; c < line.length; c++) {
            if (line[c] == '1') {
              canvas.drawRect(
                Rect.fromLTWH(
                  cursorX + c * pixelSize,
                  startY + r * pixelSize,
                  pixelSize,
                  pixelSize,
                ),
                _paint,
              );
            }
          }
        }
        cursorX += (charWidth + charSpacing) * pixelSize;
      } else {
        // Fallback space
        cursorX += (3 + charSpacing) * pixelSize;
      }
    }
  }

  /// Calculates total pixel width of text string.
  static double measureTextWidth(String text, double pixelSize, {double charSpacing = 1.0}) {
    double width = 0.0;
    final String upper = text.toUpperCase();
    for (int i = 0; i < upper.length; i++) {
      final String char = upper[i];
      final List<String>? glyph = _font3x5[char];
      final int charWidth = glyph != null ? glyph[0].length : 3;
      width += (charWidth + charSpacing) * pixelSize;
    }
    return width;
  }

  // --------------------------------------------------------------------------
  // PROCEDURAL SPRITES: CPU DIE LOGO, THERMAL PASTE BLOB, WARNING TRIANGLE
  // --------------------------------------------------------------------------

  /// Engraved Microchip Retro Logo (16x16 pixel matrix).
  static const List<String> microchipMatrix = [
    "......####......",
    ".....######.....",
    "..##.##..##.##..",
    "..##.##..##.##..",
    ".####......####.",
    ".####.####.####.",
    "##..#.####.#..##",
    "##..#.####.#..##",
    "##..#.####.#..##",
    "##..#.####.#..##",
    ".####.####.####.",
    ".####......####.",
    "..##.##..##.##..",
    "..##.##..##.##..",
    ".....######.....",
    "......####......",
  ];

  /// Multi-layered Thermal Paste Droplet (14x14 pixel matrix).
  /// Multi-layered: Dark outer rim, viscous gray body, lighter core, glossy white highlight.
  static const List<String> pasteMatrix = [
    "     DDDD     ",
    "   DDBMMBDD   ",
    "  DBMLLLMMBD  ",
    " DBMWWLLMMMBD ",
    " DBMWWLLMMMBD ",
    " DBMLLLLMMMBD ",
    "DBMMLLLLMMMMBD",
    "DBMMMMMMMMMMBD",
    "DBMMMMMMMMMMBD",
    " DBMLLMMMMMMBD",
    " DBMLLMMMMMMBD",
    "  DBMMMMMMBD  ",
    "   DDBBBBBD   ",
    "     DDDD     ",
  ];

  /// Procedural Warning Hazard Triangle (11x10 pixel matrix).
  static const List<String> warningTriangleMatrix = [
    "     B     ",
    "    BYB    ",
    "   BY!YB   ",
    "   BY!YB   ",
    "  BYY!YYB  ",
    "  BYY!YYB  ",
    " BYYYYYYYB ",
    " BYYY!YYYB ",
    "BYYYYYYYYYB",
    "BBBBBBBBBBB",
  ];
}

/// CustomPainter orchestrating all procedurally generated 16-bit retro graphics.
class ZeroGThermalPainter extends CustomPainter {
  final double ihsSize;
  final double socketSize;
  final Offset pastePos;
  final double pasteRadius;
  final List<List<bool>> coverageGrid;
  final int gridResolution;
  final int cpuTemp;
  final int coveragePercentage;
  final double timeRemaining;
  final bool isPulseActive;
  final double pulseWarningBlink;
  final double tiltX;
  final double tiltY;
  final List<PixelSpark> sparks;
  final GameStatus status;

  ZeroGThermalPainter({
    required this.ihsSize,
    required this.socketSize,
    required this.pastePos,
    required this.pasteRadius,
    required this.coverageGrid,
    required this.gridResolution,
    required this.cpuTemp,
    required this.coveragePercentage,
    required this.timeRemaining,
    required this.isPulseActive,
    required this.pulseWarningBlink,
    required this.tiltX,
    required this.tiltY,
    required this.sparks,
    required this.status,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2.0, size.height / 2.0);

    // 1. Draw Motherboard PCB Background (Circuit traces, vias, SMD components)
    _drawMotherboardPCB(canvas, size, center);

    // 2. Draw CPU Socket & LGA Gold Pin Grid (Hazard Zone)
    _drawSocketAndPins(canvas, center);

    // 3. Draw CPU IHS (Play Area) & Engraved Microchip Logo
    _drawCpuIhs(canvas, center);

    // 4. Draw Persistent Thermal Paste Trail on 20x20 Grid
    _drawCoverageTrail(canvas, center);

    // 5. Draw Thermal Paste Player Entity (Viscous multi-layered glossy blob)
    _drawThermalPasteBlob(canvas, center);

    // 6. Draw Procedural Sparks & Particle Effects
    _drawSparks(canvas, center);

    // 7. Draw Procedural Retro UI / HUD (CPU Temp, Coverage %, Timer, Alert Banners)
    _drawRetroHud(canvas, size, center);

    // 8. Draw Subtle Red Vignette & Warning Banner if Anti-Gravity Pulse Active
    if (isPulseActive) {
      _drawAntiGravityPulseAlert(canvas, size, center);
    }
  }

  // --------------------------------------------------------------------------
  // 1. MOTHERBOARD PCB BACKGROUND (Procedural Traces, Vias & SMD Components)
  // --------------------------------------------------------------------------
  void _drawMotherboardPCB(Canvas canvas, Size size, Offset center) {
    // Dark tech-slate green solder mask canvas
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(0, 0, size.width, size.height), const Color(0xFF0A140E));

    // Subtle silkscreen PCB hatch dots
    const double dotSpacing = 16.0;
    const Color pcbDotColor = Color(0xFF0E1E16);
    for (double y = 8; y < size.height; y += dotSpacing) {
      for (double x = 8; x < size.width; x += dotSpacing) {
        PixelArtRenderer.drawPixel(canvas, x, y, 2.0, pcbDotColor);
      }
    }

    // Procedural copper & green circuit traces running around socket
    const Color copperTrace = Color(0xFFB45309);
    const Color greenTrace = Color(0xFF15803D);
    const Color viaGold = Color(0xFFEAB308);

    final double halfSock = socketSize / 2.0;

    // North VRM circuit traces
    for (int i = -3; i <= 3; i++) {
      final double tx = center.dx + i * 28.0;
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(tx, 14, 3, center.dy - halfSock - 30), greenTrace);
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(tx - 1, 12, 5, 5), viaGold);
    }

    // South PCIe traces
    for (int i = -4; i <= 4; i++) {
      final double tx = center.dx + i * 22.0;
      final double startY = center.dy + halfSock + 26;
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(tx, startY, 2, size.height - startY - 20), copperTrace);
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(tx - 1, size.height - 24, 4, 4), viaGold);
    }

    // East memory bus traces
    for (int i = -3; i <= 3; i++) {
      final double ty = center.dy + i * 26.0;
      final double startX = center.dx + halfSock + 24;
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(startX, ty, size.width - startX - 12, 2), greenTrace);
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(size.width - 16, ty - 1, 4, 4), viaGold);
    }

    // SMD 0805 Resistors (Dark core with silver solder end electrodes)
    void drawSmdResistor(double x, double y, bool vertical) {
      if (vertical) {
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x, y, 5, 2), const Color(0xFFCBD5E1));
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x, y + 2, 5, 6), const Color(0xFF1E293B));
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x, y + 8, 5, 2), const Color(0xFFCBD5E1));
      } else {
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x, y, 2, 5), const Color(0xFFCBD5E1));
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x + 2, y, 6, 5), const Color(0xFF1E293B));
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x + 8, y, 2, 5), const Color(0xFFCBD5E1));
      }
    }

    // SMD Ceramic Capacitors (Amber/tan MLCC body with silver ends)
    void drawSmdCapacitor(double x, double y, bool vertical) {
      if (vertical) {
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x, y, 6, 2), const Color(0xFFCBD5E1));
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x, y + 2, 6, 7), const Color(0xFF9A6A38));
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x, y + 9, 6, 2), const Color(0xFFCBD5E1));
      } else {
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x, y, 2, 6), const Color(0xFFCBD5E1));
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x + 2, y, 7, 6), const Color(0xFF9A6A38));
        PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x + 9, y, 2, 6), const Color(0xFFCBD5E1));
      }
    }

    // Place realistic SMD components around motherboard perimeter
    drawSmdResistor(center.dx - halfSock - 28, center.dy - 60, true);
    drawSmdCapacitor(center.dx - halfSock - 28, center.dy - 40, true);
    drawSmdResistor(center.dx - halfSock - 28, center.dy + 30, true);
    drawSmdCapacitor(center.dx - halfSock - 28, center.dy + 50, true);

    drawSmdCapacitor(center.dx + halfSock + 16, center.dy - 50, true);
    drawSmdResistor(center.dx + halfSock + 16, center.dy - 30, true);
    drawSmdCapacitor(center.dx + halfSock + 16, center.dy + 40, true);

    drawSmdResistor(center.dx - 80, center.dy - halfSock - 22, false);
    drawSmdCapacitor(center.dx - 50, center.dy - halfSock - 22, false);
    drawSmdResistor(center.dx + 40, center.dy - halfSock - 22, false);
    drawSmdCapacitor(center.dx + 70, center.dy - halfSock - 22, false);

    // VRM Inductor Chokes (Top left power delivery)
    for (int i = 0; i < 2; i++) {
      final double cx = center.dx - halfSock - 36;
      final double cy = center.dy - 110 + i * 26;
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(cx, cy, 18, 18), const Color(0xFF1E2421));
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(cx + 2, cy + 2, 14, 14), const Color(0xFF2C3530));
      PixelArtRenderer.drawText(canvas, 'R33', cx + 3, cy + 6, 1.0, const Color(0xFF64748B));
    }
  }

  // --------------------------------------------------------------------------
  // 2. CPU SOCKET & LGA GOLD PIN BORDER (HAZARD ZONE)
  // --------------------------------------------------------------------------
  void _drawSocketAndPins(Canvas canvas, Offset center) {
    final Rect socketRect = Rect.fromCenter(center: center, width: socketSize, height: socketSize);

    // Socket outer retention frame (Dark textured plastic/metal)
    PixelArtRenderer.drawRect(canvas, socketRect, const Color(0xFF18201A));

    // Outer frame chamfered border
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(socketRect.left, socketRect.top, socketSize, 4), const Color(0xFF2D3A30));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(socketRect.left, socketRect.bottom - 4, socketSize, 4), const Color(0xFF0F1410));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(socketRect.left, socketRect.top, 4, socketSize), const Color(0xFF2D3A30));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(socketRect.right - 4, socketRect.top, 4, socketSize), const Color(0xFF0F1410));

    // Socket Retention Bracket Arm (Right side)
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(socketRect.right - 8, socketRect.top + 20, 6, socketSize - 40), const Color(0xFF64748B));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(socketRect.right - 6, socketRect.bottom - 24, 16, 6), const Color(0xFF94A3B8));

    // Torx mounting screws in 4 corners of socket
    void drawMountingScrew(double x, double y) {
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x - 5, y - 5, 10, 10), const Color(0xFF334155));
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(x - 3, y - 3, 6, 6), const Color(0xFF64748B));
      PixelArtRenderer.drawPixel(canvas, x - 1, y - 1, 2, const Color(0xFF0F172A));
    }

    drawMountingScrew(socketRect.left + 12, socketRect.top + 12);
    drawMountingScrew(socketRect.right - 14, socketRect.top + 12);
    drawMountingScrew(socketRect.left + 12, socketRect.bottom - 12);
    drawMountingScrew(socketRect.right - 14, socketRect.bottom - 12);

    // Pin 1 Gold Alignment Triangle (Top-Left corner of socket)
    final double p1x = socketRect.left + 8;
    final double p1y = socketRect.top + 8;
    PixelArtRenderer.drawPixelMatrix(
      canvas,
      p1x,
      p1y,
      1.5,
      [
        "####",
        "###.",
        "##..",
        "#...",
      ],
      {"#": const Color(0xFFFBBF24)},
    );

    // LGA Gold Pin Grid surrounding the IHS
    // If thermal paste enters this area, it causes a short circuit!
    final double halfIhs = ihsSize / 2.0;
    const double pinStep = 6.0;

    for (double py = socketRect.top + 12; py <= socketRect.bottom - 14; py += pinStep) {
      for (double px = socketRect.left + 12; px <= socketRect.right - 14; px += pinStep) {
        // Skip area occupied by the silver CPU IHS
        if (px >= center.dx - halfIhs - 2 &&
            px <= center.dx + halfIhs + 2 &&
            py >= center.dy - halfIhs - 2 &&
            py <= center.dy + halfIhs + 2) {
          continue;
        }

        // Draw delicate gold LGA contact pin
        PixelArtRenderer.drawPixel(canvas, px, py, 2.0, const Color(0xFFEAB308));
        PixelArtRenderer.drawPixel(canvas, px + 1, py + 1, 1.0, const Color(0xFFFDE68A));
      }
    }
  }

  // --------------------------------------------------------------------------
  // 3. CPU IHS (PLAY AREA) & ENGRAVED MICROCHIP LOGO
  // --------------------------------------------------------------------------
  void _drawCpuIhs(Canvas canvas, Offset center) {
    final Rect ihsRect = Rect.fromCenter(center: center, width: ihsSize, height: ihsSize);

    // Outer nickel-plated copper IHS perimeter with chamfered metallic borders
    PixelArtRenderer.drawRect(canvas, ihsRect, const Color(0xFF94A3B8));

    // Metallic beveled highlights & shadows
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(ihsRect.left, ihsRect.top, ihsSize, 3), const Color(0xFFE2E8F0));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(ihsRect.left, ihsRect.top, 3, ihsSize), const Color(0xFFE2E8F0));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(ihsRect.left, ihsRect.bottom - 3, ihsSize, 3), const Color(0xFF475569));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(ihsRect.right - 3, ihsRect.top, 3, ihsSize), const Color(0xFF475569));

    // Inner plate surface (Brushed metallic silver plate)
    final Rect innerIhs = Rect.fromLTWH(ihsRect.left + 4, ihsRect.top + 4, ihsSize - 8, ihsSize - 8);
    PixelArtRenderer.drawRect(canvas, innerIhs, const Color(0xFFA1A1AA));

    // Subtle horizontal brushed metal grain dithering
    for (double y = innerIhs.top + 4; y < innerIhs.bottom - 4; y += 4) {
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(innerIhs.left + 4, y, innerIhs.width - 8, 1), const Color(0xFF8E8E93));
    }

    // 4 Corner Retention Notches
    const double notchSize = 8.0;
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(ihsRect.left, ihsRect.top, notchSize, notchSize), const Color(0xFF64748B));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(ihsRect.right - notchSize, ihsRect.top, notchSize, notchSize), const Color(0xFF64748B));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(ihsRect.left, ihsRect.bottom - notchSize, notchSize, notchSize), const Color(0xFF64748B));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(ihsRect.right - notchSize, ihsRect.bottom - notchSize, notchSize, notchSize), const Color(0xFF64748B));

    // Engraved retro microchip logo in the center of the CPU IHS
    final double logoPixelSize = (ihsSize * 0.15) / 16.0;
    final double logoStartX = center.dx - (16 * logoPixelSize) / 2.0;
    final double logoStartY = center.dy - (16 * logoPixelSize) / 2.0;

    PixelArtRenderer.drawPixelMatrix(
      canvas,
      logoStartX,
      logoStartY,
      logoPixelSize,
      PixelArtRenderer.microchipMatrix,
      {"#": const Color(0xFF64748B)},
    );

    // Laser-etched chip markings
    PixelArtRenderer.drawText(canvas, 'PROC-Z1', center.dx - 18, logoStartY - 10, 1.0, const Color(0xFF64748B));
    PixelArtRenderer.drawText(canvas, 'ZERO-G', center.dx - 16, logoStartY + 16 * logoPixelSize + 3, 1.0, const Color(0xFF64748B));
  }

  // --------------------------------------------------------------------------
  // 4. PERSISTENT THERMAL PASTE TRAIL ON 20x20 GRID
  // --------------------------------------------------------------------------
  void _drawCoverageTrail(Canvas canvas, Offset center) {
    final double halfIhs = ihsSize / 2.0;
    final double cellSize = ihsSize / gridResolution;
    final double startX = center.dx - halfIhs;
    final double startY = center.dy - halfIhs;

    const Color pasteCoreColor = Color(0xFF64748B);
    const Color pasteDitherColor = Color(0xFF78889B);
    const Color pasteEdgeColor = Color(0xFF475569);

    for (int r = 0; r < gridResolution; r++) {
      for (int c = 0; c < gridResolution; c++) {
        if (coverageGrid[r][c]) {
          final double cx = startX + c * cellSize;
          final double cy = startY + r * cellSize;
          final Rect cellRect = Rect.fromLTWH(cx, cy, cellSize, cellSize);

          // Fill cell with thermal paste compound
          PixelArtRenderer.drawRect(canvas, cellRect, pasteCoreColor);

          // Procedural paste dither texture
          if ((r + c) % 2 == 0) {
            PixelArtRenderer.drawPixel(canvas, cx + 2, cy + 2, 2.0, pasteDitherColor);
          }

          // Dark meniscus line at the outer unspread boundary
          if (r > 0 && !coverageGrid[r - 1][c]) {
            PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(cx, cy, cellSize, 1.5), pasteEdgeColor);
          }
          if (r < gridResolution - 1 && !coverageGrid[r + 1][c]) {
            PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(cx, cy + cellSize - 1.5, cellSize, 1.5), pasteEdgeColor);
          }
          if (c > 0 && !coverageGrid[r][c - 1]) {
            PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(cx, cy, 1.5, cellSize), pasteEdgeColor);
          }
          if (c < gridResolution - 1 && !coverageGrid[r][c + 1]) {
            PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(cx + cellSize - 1.5, cy, 1.5, cellSize), pasteEdgeColor);
          }
        }
      }
    }
  }

  // --------------------------------------------------------------------------
  // 5. THERMAL PASTE PLAYER ENTITY (Multi-Layered Viscous Glossy Pixel Blob)
  // --------------------------------------------------------------------------
  void _drawThermalPasteBlob(Canvas canvas, Offset center) {
    final double px = center.dx + pastePos.dx;
    final double py = center.dy + pastePos.dy;

    // 14x14 matrix scaled so total width ≈ pasteRadius * 2
    final double blobPixelSize = (pasteRadius * 2.0) / 14.0;
    final double startX = px - 7.0 * blobPixelSize;
    final double startY = py - 7.0 * blobPixelSize;

    // Palette with glossy specular reflection
    final Map<String, Color> pastePalette = {
      'D': const Color(0xFF33373D), // Viscous dark perimeter
      'B': const Color(0xFF4A525A), // Outer body
      'M': const Color(0xFF7B848E), // Medium viscous paste
      'L': const Color(0xFFA3ABB5), // Light reflective core
      'W': const Color(0xFFFFFFFF), // Glossy fluid specular highlight!
    };

    PixelArtRenderer.drawPixelMatrix(
      canvas,
      startX,
      startY,
      blobPixelSize,
      PixelArtRenderer.pasteMatrix,
      pastePalette,
    );
  }

  // --------------------------------------------------------------------------
  // 6. PROCEDURAL SPARKS & PARTICLE EFFECTS
  // --------------------------------------------------------------------------
  void _drawSparks(Canvas canvas, Offset center) {
    for (final spark in sparks) {
      final double sx = center.dx + spark.pos.dx;
      final double sy = center.dy + spark.pos.dy;
      PixelArtRenderer.drawPixel(canvas, sx, sy, 3.0, spark.color);
    }
  }

  // --------------------------------------------------------------------------
  // 7. PROCEDURAL RETRO UI / HUD (CPU Temp, Coverage %, Timer, Gauges)
  // --------------------------------------------------------------------------
  void _drawRetroHud(Canvas canvas, Size size, Offset center) {
    final double hudPixelSize = 2.0;

    // --- TOP BAR: CPU TEMP & COVERAGE ---
    const double topMargin = 28.0;

    // Left HUD Box: CPU TEMPERATURE
    final Color tempColor = cpuTemp >= 88
        ? const Color(0xFFEF4444)
        : (cpuTemp >= 70 ? const Color(0xFFF59E0B) : const Color(0xFF10B981));

    PixelArtRenderer.drawText(canvas, 'SUHU CPU', 16, topMargin, 1.5, const Color(0xFF9CA3AF));
    final String tempStr = '${cpuTemp.toString().padLeft(3, '0')}°C';
    PixelArtRenderer.drawText(canvas, tempStr, 16, topMargin + 12, hudPixelSize, tempColor);

    // Temperature bar gauge (6 blocks)
    for (int i = 0; i < 6; i++) {
      final double blockX = 16.0 + i * 11.0;
      final double blockY = topMargin + 26.0;
      final bool isFilled = ((cpuTemp - 40) / 60.0 * 6.0) >= (i + 1);
      final Color barColor = isFilled ? tempColor : const Color(0xFF1F2937);
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(blockX, blockY, 9, 4), barColor);
    }

    // Right HUD Box: COVERAGE %
    final double rightBoxX = size.width - 110.0;
    final Color coverColor = coveragePercentage >= 85
        ? const Color(0xFF10B981)
        : const Color(0xFF38BDF8);

    PixelArtRenderer.drawText(canvas, 'CAKUPAN', rightBoxX, topMargin, 1.5, const Color(0xFF9CA3AF));
    final String coverStr = '${coveragePercentage.toString().padLeft(3, ' ')}%';
    PixelArtRenderer.drawText(canvas, coverStr, rightBoxX, topMargin + 12, hudPixelSize, coverColor);

    // Coverage bar gauge with target 85% tick mark
    for (int i = 0; i < 6; i++) {
      final double blockX = rightBoxX + i * 11.0;
      final double blockY = topMargin + 26.0;
      final bool isFilled = (coveragePercentage / 100.0 * 6.0) >= (i + 1);
      final Color barColor = isFilled ? coverColor : const Color(0xFF1F2937);
      PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(blockX, blockY, 9, 4), barColor);
    }
    // Target 85% indicator arrow/dot
    PixelArtRenderer.drawPixel(canvas, rightBoxX + 5 * 11.0, topMargin + 32.0, 2.0, const Color(0xFFFBBF24));

    // Center Timer Countdown
    final String timeStr = '${timeRemaining.toStringAsFixed(1)}S';
    final double timeWidth = PixelArtRenderer.measureTextWidth(timeStr, hudPixelSize);
    final double timeX = (size.width - timeWidth) / 2.0;

    final double timerLabelW = PixelArtRenderer.measureTextWidth('WAKTU', 1.2);
    PixelArtRenderer.drawText(canvas, 'WAKTU', (size.width - timerLabelW) / 2.0, topMargin, 1.2, const Color(0xFF64748B));
    PixelArtRenderer.drawText(
      canvas,
      timeStr,
      timeX,
      topMargin + 12,
      hudPixelSize,
      timeRemaining <= 5.0 ? const Color(0xFFEF4444) : const Color(0xFFF3F4F6),
    );

    // Tilt Leveler Spirit Indicator (Upper center just above socket)
    final double gyroY = center.dy - socketSize / 2.0 - 24.0;
    final double gyroX = center.dx;
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(gyroX - 22, gyroY - 6, 44, 12), const Color(0xFF111827));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(gyroX - 22, gyroY - 6, 44, 1), const Color(0xFF374151));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(gyroX - 22, gyroY + 5, 44, 1), const Color(0xFF374151));

    // Center crosshair mark
    PixelArtRenderer.drawPixel(canvas, gyroX - 1, gyroY - 3, 3, const Color(0xFF10B981).withValues(alpha: 0.4));

    // Current tilt indicator dot (responsive 2D bubble indicator!)
    final double bubbleX = (gyroX + (tiltX / 3.0) * 16.0).clamp(gyroX - 18.0, gyroX + 18.0);
    final double bubbleY = (gyroY + (tiltY / 3.0) * 3.5).clamp(gyroY - 4.0, gyroY + 4.0);
    PixelArtRenderer.drawPixel(canvas, bubbleX - 1.5, bubbleY - 1.5, 4.0, const Color(0xFF22C55E));
  }

  // --------------------------------------------------------------------------
  // 8. ANTI-GRAVITY PULSE WARNING ALERT & RED FLASH VIGNETTE
  // --------------------------------------------------------------------------
  void _drawAntiGravityPulseAlert(Canvas canvas, Size size, Offset center) {
    // Subtle red alert pulse screen tint
    final double pulseAlpha = 0.15 + 0.10 * sin(pulseWarningBlink);
    final Color alertTint = Color.fromRGBO(239, 68, 68, pulseAlpha);
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(0, 0, size.width, size.height), alertTint);

    // Red warning border around socket
    const double borderWidth = 3.0;
    final Rect alertBorder = Rect.fromCenter(center: center, width: socketSize + 8, height: socketSize + 8);
    final Color warningBorderColor = (pulseWarningBlink.toInt() % 2 == 0)
        ? const Color(0xFFEF4444)
        : const Color(0xFFFBBF24);

    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(alertBorder.left, alertBorder.top, alertBorder.width, borderWidth), warningBorderColor);
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(alertBorder.left, alertBorder.bottom - borderWidth, alertBorder.width, borderWidth), warningBorderColor);
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(alertBorder.left, alertBorder.top, borderWidth, alertBorder.height), warningBorderColor);
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(alertBorder.right - borderWidth, alertBorder.top, borderWidth, alertBorder.height), warningBorderColor);

    // Animated blinking retro warning triangle & banner
    final double bannerY = center.dy + socketSize / 2.0 + 16.0;
    final double bannerWidth = size.width - 48.0;
    final double bannerX = 24.0;

    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(bannerX, bannerY, bannerWidth, 24), const Color(0xFF1C1917));
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(bannerX, bannerY, bannerWidth, 2), warningBorderColor);
    PixelArtRenderer.drawRect(canvas, Rect.fromLTWH(bannerX, bannerY + 22, bannerWidth, 2), warningBorderColor);

    // Blinking Warning Hazard Triangle
    final Map<String, Color> trianglePalette = {
      'B': const Color(0xFF1E2022),
      'Y': (pulseWarningBlink.toInt() % 2 == 0) ? const Color(0xFFEF4444) : const Color(0xFFFBBF24),
      '!': const Color(0xFF000000),
    };

    PixelArtRenderer.drawPixelMatrix(
      canvas,
      bannerX + 8,
      bannerY + 4,
      1.5,
      PixelArtRenderer.warningTriangleMatrix,
      trianglePalette,
    );

    PixelArtRenderer.drawPixelMatrix(
      canvas,
      bannerX + bannerWidth - 24,
      bannerY + 4,
      1.5,
      PixelArtRenderer.warningTriangleMatrix,
      trianglePalette,
    );

    const String bannerText = 'BAHAYA: PULSA ZERO-G!';
    final double textW = PixelArtRenderer.measureTextWidth(bannerText, 1.6);
    PixelArtRenderer.drawText(
      canvas,
      bannerText,
      (size.width - textW) / 2.0,
      bannerY + 8,
      1.6,
      warningBorderColor,
    );
  }

  @override
  bool shouldRepaint(covariant ZeroGThermalPainter oldDelegate) {
    return true; // Driven at 60 FPS by the Ticker loop
  }
}
