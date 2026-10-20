/// Model game Tebak Harga (lokal, dari katalog bundled).
class GameQuestion {
  const GameQuestion({
    required this.questionId,
    required this.product,
    required this.specs,
    required this.hint,
  });

  final String questionId;
  final String product;
  final String specs;
  final String hint;

  factory GameQuestion.fromJson(Map<String, dynamic> json) =>
      GameQuestion(
        questionId: json['question_id'] as String? ?? '',
        product: json['product'] as String? ?? '',
        specs: json['specs'] as String? ?? '',
        hint: json['hint'] as String? ?? '',
      );
}

class GuessResult {
  const GuessResult({
    required this.actualPrice,
    required this.difference,
    required this.score,
  });

  final int actualPrice;
  final int difference;
  final int score;

  factory GuessResult.fromJson(Map<String, dynamic> json) =>
      GuessResult(
        actualPrice: (json['actual_price'] as num?)?.toInt() ?? 0,
        difference: (json['difference'] as num?)?.toInt() ?? 0,
        score: (json['score'] as num?)?.toInt() ?? 0,
      );
}

/// Skor = round(max(0, 100 − |tebakan − asli| / asli × 100)).
int scoreGuess(int guess, int actual) {
  if (actual <= 0) return 0;
  return (100 - ((guess - actual).abs() / actual * 100))
      .clamp(0, 100)
      .round();
}
