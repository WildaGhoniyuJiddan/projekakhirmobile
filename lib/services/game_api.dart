import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/models/game_models.dart';

import 'local_catalog.dart';

final gameApiProvider = Provider<GameApi>((ref) => GameApi());

/// Game Tebak Harga — sekarang 100% lokal dari katalog bundled.
/// Skor memakai rumus yang sama: round(max(0, 100 − |selisih|/asli × 100)).
class GameApi {
  final _rng = Random();
  final _pending = <String, int>{};
  var _seq = 0;

  Future<GameQuestion> getQuestion() async {
    final item = await LocalCatalog.randomGameItem(_rng);
    final qid = 'q_${DateTime.now().millisecondsSinceEpoch}_${_seq++}';
    _pending[qid] = item.price;
    final shortModel =
        item.model.length > 120 ? item.model.substring(0, 120) : item.model;
    return GameQuestion(
      questionId: qid,
      product: shortModel,
      specs: 'Komponen PC dari katalog retail • '
          'Tebak harga pasarnya dalam Rupiah',
      hint: _priceHint(item.price),
    );
  }

  Future<GuessResult> submitGuess({
    required String questionId,
    required int guessIdr,
  }) async {
    final actual = _pending.remove(questionId) ?? 0;
    final difference = guessIdr - actual;
    return GuessResult(
      actualPrice: actual,
      difference: difference,
      score: scoreGuess(guessIdr, actual),
    );
  }
}

/// Hint kisaran harga tanpa membocorkan angka pastinya.
String _priceHint(int price) {
  if (price <= 0) return 'Kisaran harga: belum tersedia';
  final jt = price / 1000000;
  if (jt < 1) return 'Kisaran harga: di bawah Rp1 juta';
  if (jt < 3) return 'Kisaran harga: Rp1–3 juta';
  if (jt < 5) return 'Kisaran harga: Rp3–5 juta';
  if (jt < 10) return 'Kisaran harga: Rp5–10 juta';
  return 'Kisaran harga: di atas Rp10 juta';
}

/// High score lokal (SharedPreferences).
class HighScoreStore {
  HighScoreStore(this._prefs);

  final SharedPreferences _prefs;

  static const _bestKey = 'game_high_score';
  static const _gamesKey = 'game_games_played';

  int get bestScore => _prefs.getInt(_bestKey) ?? 0;
  int get gamesPlayed => _prefs.getInt(_gamesKey) ?? 0;

  /// Simpan skor total permainan; kembalikan true bila rekor baru.
  Future<bool> saveScore(int totalScore) async {
    await _prefs.setInt(_gamesKey, gamesPlayed + 1);
    if (totalScore > bestScore) {
      await _prefs.setInt(_bestKey, totalScore);
      return true;
    }
    return false;
  }
}

final highScoreStoreProvider = FutureProvider<HighScoreStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return HighScoreStore(prefs);
});
