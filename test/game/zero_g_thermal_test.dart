import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/widgets/zero_g_thermal_game.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZeroGThermalGame Tests', () {
    testWidgets('renders ZeroGThermalGame in ready state with briefing modal', (tester) async {
      bool? isWinResult;
      int? scoreResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZeroGThermalGame(
              onGameFinished: (isWin, score) {
                isWinResult = isWin;
                scoreResult = score;
              },
            ),
          ),
        ),
      );

      // Verify start modal and title
      expect(find.text('PROTOKOL TERMAL ZERO-G'), findsOneWidget);
      expect(find.text('MULAI PROTOKOL'), findsOneWidget);
      expect(find.textContaining('MIRINGKAN HP'), findsOneWidget);

      // Tap MULAI PROTOKOL to start
      await tester.tap(find.text('MULAI PROTOKOL'));
      await tester.pump();

      // Start modal disappears, in-game controls appear
      expect(find.text('MULAI PROTOKOL'), findsNothing);
      expect(find.text('KALIBRASI'), findsOneWidget);
      expect(find.text('NORMAL'), findsOneWidget);

      // Tap speed toggle
      await tester.tap(find.text('NORMAL'));
      await tester.pump();
      expect(find.text('RESPONSIF'), findsOneWidget);

      // Advance clock slightly (ticker ticks)
      await tester.pump(const Duration(milliseconds: 100));

      expect(isWinResult, isNull);
      expect(scoreResult, isNull);
    });

    testWidgets('CustomPainter renders procedural pixel elements without errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ZeroGThermalGame(
              onGameFinished: (win, score) {},
            ),
          ),
        ),
      );

      // Tap to start
      await tester.tap(find.text('MULAI PROTOKOL'));
      await tester.pump();

      // Tap KALIBRASI calibration
      await tester.tap(find.text('KALIBRASI'));
      await tester.pump();

      // Test drag gesture simulation on the canvas surface
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(20, 20));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify custom painter is present
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('ZeroGThermalPainter paints all layers cleanly on canvas', (tester) async {
      final grid = List.generate(20, (_) => List.filled(20, false));
      grid[10][10] = true;
      grid[10][11] = true;

      final painter = ZeroGThermalPainter(
        ihsSize: 200.0,
        socketSize: 260.0,
        pastePos: const Offset(5, 5),
        pasteRadius: 12.0,
        coverageGrid: grid,
        gridResolution: 20,
        cpuTemp: 55,
        coveragePercentage: 12,
        timeRemaining: 24.5,
        isPulseActive: true,
        pulseWarningBlink: 2.0,
        tiltX: 1.2,
        tiltY: -0.8,
        sparks: [],
        status: GameStatus.playing,
      );

      final recorder = TestCanvas();
      painter.paint(recorder, const Size(360, 640));
      expect(painter.shouldRepaint(painter), isTrue);
    });
  });
}

class TestCanvas extends Fake implements Canvas {
  @override
  void drawRect(Rect rect, Paint paint) {
    // Verified drawRect call
  }
}
