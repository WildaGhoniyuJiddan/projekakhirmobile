import 'package:flutter/material.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/widgets/zero_g_thermal_game.dart';

/// Screen host for the Zero-G Thermal Protocol retro minigame.
class ZeroGThermalScreen extends StatefulWidget {
  const ZeroGThermalScreen({super.key});

  @override
  State<ZeroGThermalScreen> createState() => _ZeroGThermalScreenState();
}

class _ZeroGThermalScreenState extends State<ZeroGThermalScreen> {
  int _lastScore = 0;
  bool? _lastWin;

  void _onGameFinished(bool isWin, int coverageScore) {
    setState(() {
      _lastWin = isWin;
      _lastScore = coverageScore;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09120C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1C13),
        elevation: 0,
        title: const Text(
          'Protokol Termal Zero-G',
          style: TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.bold,
            color: Color(0xFF4ADE80),
            fontSize: 16,
          ),
        ),
        actions: [
          if (_lastWin != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  'Skor: $_lastScore%',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: _lastWin == true ? MonexColors.lime : Colors.redAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ZeroGThermalGame(
          onGameFinished: _onGameFinished,
        ),
      ),
    );
  }
}
