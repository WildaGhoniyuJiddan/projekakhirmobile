/// Model tren harga (lokal, statistik dari katalog bundled).
class TrendPoint {
  const TrendPoint({required this.date, required this.price});

  final DateTime date;
  final int price;

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
        date: DateTime.parse(json['date'] as String),
        price: (json['price'] as num).toInt(),
      );
}

class TrendData {
  const TrendData({
    required this.query,
    required this.days,
    required this.points,
    required this.min,
    required this.max,
    required this.avg,
    required this.changePercent,
    required this.summary,
  });

  final String query;
  final int days;
  final List<TrendPoint> points;
  final int min;
  final int max;
  final double avg;
  final double changePercent;
  final String summary;

  factory TrendData.fromJson(Map<String, dynamic> json) => TrendData(
        query: json['query'] as String? ?? '',
        days: (json['days'] as num?)?.toInt() ?? 30,
        points: ((json['points'] as List?) ?? [])
            .map((e) => TrendPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        min: (json['min'] as num?)?.toInt() ?? 0,
        max: (json['max'] as num?)?.toInt() ?? 0,
        avg: (json['avg'] as num?)?.toDouble() ?? 0,
        changePercent:
            (json['change_percent'] as num?)?.toDouble() ?? 0,
        summary: json['summary'] as String? ?? '',
      );

  /// Ringkasan deskriptif lokal (fallback bila server tidak mengirim summary).
  /// Murni deskriptif — tanpa prediksi harga masa depan.
  String localSummary() {
    final dir = changePercent < -0.5
        ? 'turun'
        : changePercent > 0.5
            ? 'naik'
            : 'stabil';
    return 'Harga $dir ${changePercent.abs().toStringAsFixed(1)}% '
        'dalam $days hari terakhir (rata-rata periode ini '
        'Rp ${avg.round()}).';
  }
}
