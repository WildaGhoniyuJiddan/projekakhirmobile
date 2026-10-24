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

  group('BuildCardData serialization roundtrip', () {
    test('BuildItem toJson & fromJson', () {
      const item = BuildItem(component: 'RAM', name: 'Corsair 16GB', price: 750000);
      final json = item.toJson();
      expect(json, {
        'component': 'RAM',
        'name': 'Corsair 16GB',
        'price': 750000,
      });
      final restored = BuildItem.fromJson(json);
      expect(restored.component, item.component);
      expect(restored.name, item.name);
      expect(restored.price, item.price);
    });

    test('BuildCardData toJson & fromJson dengan note', () {
      const card = BuildCardData(
        items: [
          BuildItem(component: 'CPU', name: 'Core i5-12400F', price: 2100000),
          BuildItem(component: 'GPU', name: 'RTX 3060', price: 4200000),
        ],
        total: 6300000,
        note: 'Best value 1080p gaming',
      );
      final json = card.toJson();
      expect(json['total'], 6300000);
      expect(json['note'], 'Best value 1080p gaming');
      expect((json['items'] as List).length, 2);

      final restored = BuildCardData.fromJson(json);
      expect(restored.total, 6300000);
      expect(restored.note, 'Best value 1080p gaming');
      expect(restored.items.length, 2);
      expect(restored.items.first.name, 'Core i5-12400F');
    });

    test('BuildCardData toJson tanpa note', () {
      const card = BuildCardData(
        items: [],
        total: 0,
      );
      final json = card.toJson();
      expect(json.containsKey('note'), isFalse);
      expect(json['total'], 0);
    });
  });
}

