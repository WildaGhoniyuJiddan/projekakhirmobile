import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:worthbang/services/features/game_api.dart';
import 'package:worthbang/models/game_models.dart';

void main() {
  group('scoreGuess (rumus kontrak B8)', () {
    test('tepat = 100', () {
      expect(scoreGuess(4500000, 4500000), 100);
    });

    test('selisih 10% = 90', () {
      expect(scoreGuess(4950000, 4500000), 90);
      expect(scoreGuess(4050000, 4500000), 90);
    });

    test('selisih ≥100% = 0', () {
      expect(scoreGuess(9000000, 4500000), 0);
      expect(scoreGuess(0, 4500000), 0);
    });

    test('actual 0 → 0 (anti divide-by-zero)', () {
      expect(scoreGuess(1000, 0), 0);
    });
  });

  group('GameQuestion/GuessResult.fromJson (kontrak B8)', () {
    test('question tanpa harga', () {
      final q = GameQuestion.fromJson({
        'question_id': 'q-1',
        'product': 'RTX 4060 8GB',
        'specs': 'GPU ...',
        'hint': '...',
      });
      expect(q.questionId, 'q-1');
      expect(q.product, 'RTX 4060 8GB');
    });

    test('submit result', () {
      final r = GuessResult.fromJson({
        'actual_price': 4600000,
        'difference': -600000,
        'score': 87,
      });
      expect(r.score, 87);
      expect(r.difference, -600000);
    });
  });

  group('HighScoreStore', () {
    test('rekor baru tersimpan, skor rendah tidak menimpa', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = HighScoreStore(prefs);

      expect(store.bestScore, 0);
      expect(await store.saveScore(320), isTrue);
      expect(store.bestScore, 320);
      expect(store.gamesPlayed, 1);

      expect(await store.saveScore(150), isFalse);
      expect(store.bestScore, 320);
      expect(store.gamesPlayed, 2);
    });
  });
}
