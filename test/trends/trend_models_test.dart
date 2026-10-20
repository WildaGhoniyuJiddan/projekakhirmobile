import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/models/trend_models.dart';

void main() {
  group('TrendData.fromJson (kontrak B5)', () {
    test('parse response lengkap', () {
      final data = TrendData.fromJson({
        'query': 'RTX 4060',
        'days': 30,
        'points': [
          {'date': '2026-08-30', 'price': 4700000},
          {'date': '2026-09-29', 'price': 4500000},
        ],
        'min': 4400000,
        'max': 4800000,
        'avg': 4600000,
        'change_percent': -6.7,
        'summary': 'Turun 6.7% dalam 30 hari.',
      });
      expect(data.query, 'RTX 4060');
      expect(data.points.length, 2);
      expect(data.points.first.date, DateTime(2026, 8, 30));
      expect(data.min, 4400000);
      expect(data.max, 4800000);
      expect(data.avg, 4600000);
      expect(data.changePercent, -6.7);
      expect(data.summary, contains('6.7%'));
    });

    test('toleran field hilang', () {
      final data = TrendData.fromJson({'query': 'X'});
      expect(data.points, isEmpty);
      expect(data.min, 0);
      expect(data.summary, '');
    });
  });

  group('localSummary (deskriptif, tanpa prediksi)', () {
    test('turun', () {
      const d = TrendData(
        query: 'X', days: 30, points: [], min: 1, max: 2,
        avg: 1500000, changePercent: -6.7, summary: '',
      );
      final s = d.localSummary();
      expect(s, contains('turun'));
      expect(s, contains('6.7%'));
      expect(s, isNot(contains('prediksi')));
      expect(s, isNot(contains('akan')));
    });

    test('naik & stabil', () {
      const up = TrendData(
        query: 'X', days: 7, points: [], min: 1, max: 2,
        avg: 100, changePercent: 3.2, summary: '',
      );
      expect(up.localSummary(), contains('naik'));
      const flat = TrendData(
        query: 'X', days: 7, points: [], min: 1, max: 2,
        avg: 100, changePercent: 0.2, summary: '',
      );
      expect(flat.localSummary(), contains('stabil'));
    });
  });
}
