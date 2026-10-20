import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/models/price_check_models.dart';
import 'package:worthbang/screens/price_check_screen.dart';
import 'package:worthbang/screens/search_screen.dart';
import 'package:worthbang/services/api_exception.dart';
import 'package:worthbang/services/price_check_api.dart';

class _MockPriceCheckApi extends PriceCheckApi {
  _MockPriceCheckApi({this.onSearch}) : super();

  final Future<List<PriceComparison>> Function({
    required String mode,
    required String query,
  })? onSearch;

  @override
  Future<List<PriceComparison>> search({
    required String mode,
    required String query,
    String? componentType,
    String condition = 'any',
  }) async {
    if (onSearch != null) {
      return onSearch!(mode: mode, query: query);
    }
    return [
      PriceComparison(
        title: 'Test Item $query',
        price: 3500000,
        source: 'tokopedia',
        similarity: 0.9,
        condition: 'baru',
      ),
    ];
  }
}

void main() {
  group('SearchFilterScreen widget tests', () {
    testWidgets('Cari produk memakai endpoint pencarian langsung', (tester) async {
      String? capturedMode;
      String? capturedQuery;

      final mockApi = _MockPriceCheckApi(
        onSearch: ({
          required mode,
          required query,
        }) async {
          capturedMode = mode;
          capturedQuery = query;
          return [
            const PriceComparison(
              title: 'GeForce RTX 3060 12GB',
              price: 4200000,
              source: 'tokopedia',
              similarity: 0.95,
              condition: 'new',
            ),
          ];
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            priceCheckApiProvider.overrideWithValue(mockApi),
          ],
          child: const MaterialApp(
            home: SearchFilterScreen(),
          ),
        ),
      );

      // Input query saja, biarkan harga kosong
      final queryField = find.byType(TextField).first;
      await tester.enterText(queryField, 'RTX 3060');

      // Tekan tombol Cari
      final searchButton = find.widgetWithText(FilledButton, 'Cari');
      await tester.tap(searchButton);
      await tester.pumpAndSettle();

      expect(capturedMode, 'pc');
      expect(capturedQuery, 'RTX 3060');

      // Memastikan hasil listing tampil di layar
      expect(find.text('GeForce RTX 3060 12GB'), findsOneWidget);
      expect(find.text('tokopedia • baru'), findsOneWidget);
      expect(find.textContaining('ApiException'), findsNothing);
      await tester.tap(find.widgetWithText(FilterChip, 'Baru'));
      await tester.pumpAndSettle();
      expect(find.text('GeForce RTX 3060 12GB'), findsOneWidget);
    });

    testWidgets('Pencarian tidak memanggil endpoint analisis harga', (tester) async {
      int callCount = 0;

      final mockApi = _MockPriceCheckApi(
        onSearch: ({
          required mode,
          required query,
        }) async {
          callCount++;
          return [
            const PriceComparison(
              title: 'Fallback Result',
              price: 3000000,
              source: 'tokopedia',
              similarity: 0.9,
            ),
          ];
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            priceCheckApiProvider.overrideWithValue(mockApi),
          ],
          child: const MaterialApp(
            home: SearchFilterScreen(),
          ),
        ),
      );

      final queryField = find.byType(TextField).first;
      await tester.enterText(queryField, 'GTX 1650');
      await tester.tap(find.widgetWithText(FilledButton, 'Cari'));
      await tester.pumpAndSettle();

      expect(callCount, 1);
      expect(find.text('Fallback Result'), findsOneWidget);
    });

    testWidgets('Menampilkan pesan error yang ramah jika terjadi kegagalan jaringan', (tester) async {
      final mockApi = _MockPriceCheckApi(
        onSearch: ({
          required mode,
          required query,
        }) async {
          throw const ApiException('Tidak dapat terhubung ke server.', 503);
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            priceCheckApiProvider.overrideWithValue(mockApi),
          ],
          child: const MaterialApp(
            home: SearchFilterScreen(),
          ),
        ),
      );

      final queryField = find.byType(TextField).first;
      await tester.enterText(queryField, 'Ryzen 5');
      await tester.tap(find.widgetWithText(FilledButton, 'Cari'));
      await tester.pumpAndSettle();

      expect(find.text('Tidak dapat terhubung ke server.'), findsOneWidget);
      expect(find.textContaining('ApiException(503):'), findsNothing);
    });

    testWidgets('Mode switch PC dan Laptop dapat dipilih', (tester) async {
      String? capturedMode;

      final mockApi = _MockPriceCheckApi(
        onSearch: ({
          required mode,
          required query,
        }) async {
          capturedMode = mode;
          return [];
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            priceCheckApiProvider.overrideWithValue(mockApi),
          ],
          child: const MaterialApp(
            home: SearchFilterScreen(),
          ),
        ),
      );

      // Pilih segmen Laptop
      await tester.tap(find.text('Laptop'));
      await tester.pumpAndSettle();

      final queryField = find.byType(TextField).first;
      await tester.enterText(queryField, 'ThinkPad');
      await tester.tap(find.widgetWithText(FilledButton, 'Cari'));
      await tester.pumpAndSettle();

      expect(capturedMode, 'laptop');
    });
  });
}
