import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/features/dream_build_api.dart';

/// Test vector WB-DREAM-v1 — HARUS sama dengan contracts/README.md
/// (dihitung independen pakai Node crypto) dan publish-build (TS).
void main() {
  const cardId = '11111111-2222-3333-4444-555555555555';
  const ownerId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

  // Sengaja TIDAK urut slot: builder kanonik wajib mengurutkan.
  const items = [
    DreamBuildItem(
      slot: 'Storage',
      partName: 'ADATA Legend 850 Lite 1TB NVMe Gen4',
      price: 1299000,
    ),
    DreamBuildItem(
      slot: 'GPU',
      partName: 'ASRock Radeon RX 9070 XT Challenger 16GB',
      price: 14590000,
    ),
    DreamBuildItem(
      slot: 'CPU',
      partName: 'AMD Ryzen 5 7600',
      price: 3050000,
    ),
    DreamBuildItem(
      slot: 'RAM',
      partName: 'ADATA XPG Lancer DDR5 32GB (2x16GB) 6000MHz',
      price: 2850000,
    ),
    DreamBuildItem(
      slot: 'Motherboard',
      partName: 'MSI B650M Mortar WiFi',
      price: 2899000,
    ),
  ];

  const expectedText = 'WB-DREAM-v1\n'
      'card:11111111-2222-3333-4444-555555555555\n'
      'owner:aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\n'
      'version:1\n'
      'slot=CPU;name=AMD Ryzen 5 7600;price=3050000\n'
      'slot=Motherboard;name=MSI B650M Mortar WiFi;price=2899000\n'
      'slot=GPU;name=ASRock Radeon RX 9070 XT Challenger 16GB;price=14590000\n'
      'slot=RAM;name=ADATA XPG Lancer DDR5 32GB (2x16GB) 6000MHz;price=2850000\n'
      'slot=Storage;name=ADATA Legend 850 Lite 1TB NVMe Gen4;price=1299000\n'
      'total=24688000';

  test('teks kanonik persis seperti spek', () {
    expect(
      dreamCanonicalText(
        cardId: cardId,
        ownerId: ownerId,
        version: 1,
        items: items,
      ),
      expectedText,
    );
  });

  test('contentHash sama dengan test vector Node', () {
    expect(
      dreamContentHash(
        cardId: cardId,
        ownerId: ownerId,
        version: 1,
        items: items,
      ),
      '32c2e8b8a0bf7f5e5aebec07ca2fbd8b56cca62f0ce12b8902c70f14ac902ffa',
    );
  });

  test('cardId bytes32 = sha256 string uuid kartu', () {
    expect(
      dreamCardIdBytes32(cardId),
      '666ff6ccaa5b3c07feaa3a95d3a4bd2c46ac9e9abdb09ca9133528d3dc1e8952',
    );
  });
}
