import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glbview/glbview.dart';
import 'package:worthbang/services/pc_scene.dart';
import 'package:worthbang/services/wglb.dart';

/// Verifikasi nyata: file .wglb hasil pipeline offline + GLB hasil rakitan
/// harus bisa dibaca parser milik plugin (parser yang sama dengan yang
/// dipakai runtime native).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catalog asset terbaca dan punya varian per role', () async {
    final catalog = await WglbCatalog.load();
    expect(catalog.isEmpty, isFalse);
    for (final role in ['mobo', 'gpu', 'ram', 'cpu', 'psu', 'fan', 'case']) {
      expect(catalog.of(role), isNotEmpty, reason: 'role $role');
    }
  });

  test('setiap varian .wglb valid dan punya geometri', () async {
    final catalog = await WglbCatalog.load();
    for (final role in catalog.roles.keys) {
      for (final variant in catalog.of(role)) {
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

  test('scene rakitan bisa di-parse plugin native', () async {
    final catalog = await WglbCatalog.load();
    final parts = <WglbVariant>[];
    for (final role in ['case', 'mobo', 'cpu', 'ram', 'gpu', 'psu', 'fan']) {
      parts.add(catalog.of(role).first);
    }

    final sceneParts = <ScenePart>[];
    for (final variant in parts) {
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

  test('total triangle scene tetap dalam budget', () async {
    final catalog = await WglbCatalog.load();
    final parts = <WglbVariant>[];
    for (final role in ['case', 'mobo', 'cpu', 'ram', 'gpu', 'psu', 'fan']) {
      parts.add(catalog.of(role).first);
    }
    var tris = 0;
    for (final variant in parts) {
      final data = await File(variant.file).readAsBytes();
      tris += WglbPart.parse(data).triangleCount;
    }
    expect(tris, lessThan(60000), reason: 'budget triangles per scene');
  });
}
