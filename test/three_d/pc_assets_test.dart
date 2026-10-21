import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glbview/glbview.dart';
import 'package:worthbang/services/pc_scene.dart';
import 'package:worthbang/services/wglb.dart';

/// Verifikasi nyata: file .wglb hasil pipeline offline + GLB hasil rakitan
/// harus bisa dibaca parser milik plugin (parser yang sama dengan yang
/// dipakai runtime native).
///
/// Model aset = SATU SET PC utuh per build BuildCores (catalog v2).
/// Yang diacak di UI adalah set-nya; part tidak pernah dicampur antar set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog terbaca: beberapa set, masing-masing PC utuh', () async {
    final catalog = await WglbCatalog.load();
    expect(catalog.isEmpty, isFalse);
    expect(catalog.sets.length, greaterThanOrEqualTo(3));
    for (final set in catalog.sets) {
      expect(set.parts.length, greaterThanOrEqualTo(7), reason: set.id);
      // Satu set = satu build: tepat satu case, ada mobo dan gpu.
      expect(set.parts.where((p) => p.role == 'case').length, 1,
          reason: set.id);
      expect(set.parts.any((p) => p.role == 'mobo'), isTrue, reason: set.id);
      expect(set.parts.any((p) => p.role == 'gpu'), isTrue, reason: set.id);
    }
  });

  test('setiap part .wglb valid dan punya geometri', () async {
    final catalog = await WglbCatalog.load();
    for (final set in catalog.sets) {
      for (final variant in set.parts) {
        final data = await File(variant.file).readAsBytes();
        final part = WglbPart.parse(data);
        expect(part.vertexCount, greaterThan(0), reason: variant.id);
        expect(part.triangleCount, greaterThan(0), reason: variant.id);
        expect(part.positions.length, part.vertexCount * 3);
        expect(part.normals.length, part.vertexCount * 3);
        expect(part.indices.length, part.triangleCount * 3);
        // Indeks harus menunjuk vertex yang ada.
        for (final i in part.indices) {
          expect(i, lessThan(part.vertexCount), reason: variant.id);
        }
      }
    }
  });

  test('bentuk set masuk akal: menara tegak, bukan kubus/slab ambruk',
      () async {
    // Gerbang yang dulu TIDAK ada: tes lama cuma cek parse/normal/budget,
    // sehingga bug transform node (semua panel menumpuk jadi kubus di
    // origin) lolos. Bbox gabungan satu set harus menyerupai tower PC:
    // sisi terpanjang ~= 440mm (normalisasi pipeline), proporsi tidak
    // kubik sempurna dan tidak pipih seperti slab.
    final catalog = await WglbCatalog.load();
    for (final set in catalog.sets) {
      final min = [double.infinity, double.infinity, double.infinity];
      final max = [double.negativeInfinity, double.negativeInfinity,
        double.negativeInfinity];
      for (final variant in set.parts) {
        final data = await File(variant.file).readAsBytes();
        final part = WglbPart.parse(data);
        for (var i = 0; i < part.positions.length; i += 3) {
          for (var c = 0; c < 3; c++) {
            final v = part.positions[i + c];
            if (v < min[c]) min[c] = v;
            if (v > max[c]) max[c] = v;
          }
        }
      }
      final ext = [max[0] - min[0], max[1] - min[1], max[2] - min[2]]..sort();
      expect(ext[2], closeTo(440, 25), reason: '${set.id} sisi terpanjang');
      expect(ext[0] / ext[2], lessThan(0.7),
          reason: '${set.id} terlalu kubik: $ext');
      expect(ext[1] / ext[2], greaterThan(0.55),
          reason: '${set.id} terlalu pipih: $ext');
      // Tegak: tinggi (y) harus salah satu dari dua sisi terbesar.
      final yExt = max[1] - min[1];
      expect(yExt, greaterThanOrEqualTo(ext[1] - 1),
          reason: '${set.id} tidak tegak: y=$yExt ext=$ext');
    }
  });

  test('scene satu set utuh bisa di-parse plugin native', () async {
    final catalog = await WglbCatalog.load();
    final set = catalog.sets.first;

    final sceneParts = <ScenePart>[];
    for (final variant in set.parts) {
      final data = await File(variant.file).readAsBytes();
      final geometry = WglbPart.parse(data);
      sceneParts.add(ScenePart.fromVariant(variant, geometry));
    }

    final glb = PcScene.toGlb(sceneParts);
    expect(glb.length, greaterThan(1000));

    // Parser plugin: inilah yang akan dipakai runtime. Kalau gagal di sini,
    // model tidak akan pernah tampil di perangkat.
    final model = parseGlb(glb);
    expect(model.primitives, isNotEmpty);
    expect(model.triangleCount, greaterThan(1000));
    expect(model.vertexCount, greaterThan(1000));

    // Normal harus ter-normalisasi (parser menghitung dari file).
    for (final p in model.primitives) {
      expect(p.baseColor.length, 4);
      for (var i = 0; i < p.vertices.length; i += 12) {
        final len = (p.vertices[i + 3] * p.vertices[i + 3] +
                p.vertices[i + 4] * p.vertices[i + 4] +
                p.vertices[i + 5] * p.vertices[i + 5]) *
            (1 / 1);
        expect(len, closeTo(1.0, 0.01), reason: 'normal unit');
      }
    }
  });

  test('total triangle per set tetap dalam budget', () async {
    final catalog = await WglbCatalog.load();
    for (final set in catalog.sets) {
      var tris = 0;
      for (final variant in set.parts) {
        final data = await File(variant.file).readAsBytes();
        tris += WglbPart.parse(data).triangleCount;
      }
      expect(tris, lessThan(60000), reason: 'budget triangles set ${set.id}');
    }
  });
}
