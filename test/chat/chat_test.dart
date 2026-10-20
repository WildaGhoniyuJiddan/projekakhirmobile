import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/models/chat_models.dart';

void main() {
  group('ChatReply.fromJson (kontrak B7)', () {
    test('reply + build card', () {
      final r = ChatReply.fromJson({
        'reply': 'Berikut rakitan ...',
        'build': {
          'items': [
            {'component': 'CPU', 'name': 'Ryzen 5 5600', 'price': 1850000},
            {'component': 'GPU', 'name': 'RTX 4060 8GB', 'price': 4550000},
          ],
          'total': 6400000,
          'note': 'Estimasi pasar.',
        },
      });
      expect(r.reply, contains('rakitan'));
      expect(r.build, isNotNull);
      expect(r.build!.items.length, 2);
      expect(r.build!.items.first.component, 'CPU');
      expect(r.build!.total, 6400000);
      expect(r.build!.note, 'Estimasi pasar.');
    });

    test('reply tanpa build', () {
      final r = ChatReply.fromJson({'reply': 'Halo!'});
      expect(r.build, isNull);
    });

    test('toleran field hilang', () {
      final r = ChatReply.fromJson({});
      expect(r.reply, '');
      expect(r.build, isNull);
    });
  });

  group('ChatMessage.toJson', () {
    test('format history sesuai kontrak', () {
      const m = ChatMessage(role: 'user', text: 'rakit PC 8 juta');
      expect(m.toJson(), {'role': 'user', 'text': 'rakit PC 8 juta'});
    });
  });
}
