import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/data/hash_chain_service.dart';

HashBlock _block({
  required int id,
  required String dataJson,
  required String prevHash,
  required String timestamp,
}) =>
    HashBlock(
      id: id,
      timestampIso: timestamp,
      dataJson: dataJson,
      prevHash: prevHash,
      hash: HashChainService.computeHash(
        index: id,
        timestampIso: timestamp,
        dataJson: dataJson,
        prevHash: prevHash,
      ),
    );

void main() {
  group('HashChainService', () {
    test('computeHash deterministik & format 64 hex', () {
      final h1 = HashChainService.computeHash(
        index: 1,
        timestampIso: '2026-09-29T10:00:00Z',
        dataJson: '{"a":1}',
        prevHash: 'GENESIS',
      );
      final h2 = HashChainService.computeHash(
        index: 1,
        timestampIso: '2026-09-29T10:00:00Z',
        dataJson: '{"a":1}',
        prevHash: 'GENESIS',
      );
      expect(h1, h2);
      expect(h1.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(h1), isTrue);
    });

    test('rantai valid 3 blok → semua ok', () {
      const t = '2026-09-29T10:00:00Z';
      final b1 = _block(id: 1, dataJson: '{"q":"a"}', prevHash: 'GENESIS', timestamp: t);
      final b2 = _block(id: 2, dataJson: '{"q":"b"}', prevHash: b1.hash, timestamp: t);
      final b3 = _block(id: 3, dataJson: '{"q":"c"}', prevHash: b2.hash, timestamp: t);
      final results = HashChainService.verifyChain([b1, b2, b3]);
      expect(results.every((r) => r.ok), isTrue);
    });

    test('data blok diubah tanpa perbaiki hash → blok itu saja invalid', () {
      const t = '2026-09-29T10:00:00Z';
      final b1 = _block(id: 1, dataJson: '{"q":"a"}', prevHash: 'GENESIS', timestamp: t);
      final b2 = _block(id: 2, dataJson: '{"q":"b"}', prevHash: b1.hash, timestamp: t);
      final b3 = _block(id: 3, dataJson: '{"q":"c"}', prevHash: b2.hash, timestamp: t);
      // Penyerang ubah dataJson b2 TANPA memperbaiki hash-nya.
      final tampered = HashBlock(
        id: b2.id,
        timestampIso: b2.timestampIso,
        dataJson: '{"q":"jahat"}',
        prevHash: b2.prevHash,
        hash: b2.hash,
      );
      final results = HashChainService.verifyChain([b1, tampered, b3]);
      expect(results[0].ok, isTrue);
      expect(results[1].ok, isFalse); // hash tidak cocok dengan data
      expect(results[2].ok, isTrue); // masih me-link ke hash tersimpan b2
    });

    test('penyerang hitung ulang hash blok jahat → rantai sesudahnya putus', () {
      const t = '2026-09-29T10:00:00Z';
      final b1 = _block(id: 1, dataJson: '{"q":"a"}', prevHash: 'GENESIS', timestamp: t);
      final b2 = _block(id: 2, dataJson: '{"q":"b"}', prevHash: b1.hash, timestamp: t);
      final b3 = _block(id: 3, dataJson: '{"q":"c"}', prevHash: b2.hash, timestamp: t);
      // Penyerang canggih: ubah data + hitung ulang hash b2 agar konsisten.
      final evilHash = HashChainService.computeHash(
        index: 2, timestampIso: t,
        dataJson: '{"q":"jahat"}', prevHash: b1.hash,
      );
      final evil = HashBlock(
        id: 2, timestampIso: t, dataJson: '{"q":"jahat"}',
        prevHash: b1.hash, hash: evilHash,
      );
      final results = HashChainService.verifyChain([b1, evil, b3]);
      expect(results[0].ok, isTrue);
      expect(results[1].ok, isTrue); // konsisten sendirian...
      expect(results[2].ok, isFalse); // ...tapi rantai downstream putus
    });

    test('prevHash salah → tidak valid', () {
      const t = '2026-09-29T10:00:00Z';
      final b1 = _block(id: 1, dataJson: '{"q":"a"}', prevHash: 'GENESIS', timestamp: t);
      final b2 = HashBlock(
        id: 2,
        timestampIso: t,
        dataJson: '{"q":"b"}',
        prevHash: 'SALAH',
        hash: HashChainService.computeHash(
          index: 2, timestampIso: t, dataJson: '{"q":"b"}', prevHash: 'SALAH'),
      );
      final results = HashChainService.verifyChain([b1, b2]);
      expect(results[0].ok, isTrue);
      expect(results[1].ok, isFalse);
    });

    test('rantai kosong → hasil kosong', () {
      expect(HashChainService.verifyChain(const []), isEmpty);
    });

    test('canonicalDataJson stabil (field terurut)', () {
      final a = HashChainService.canonicalDataJson(
        mode: 'pc', query: 'RTX 4060', inputPrice: 4500000,
        score: 82.5, verdict: 'wajar',
      );
      final b = HashChainService.canonicalDataJson(
        mode: 'pc', query: 'RTX 4060', inputPrice: 4500000,
        score: 82.5, verdict: 'wajar',
      );
      expect(a, b);
      expect(a.indexOf('"input_price"'), lessThan(a.indexOf('"query"')));
    });
  });
}
