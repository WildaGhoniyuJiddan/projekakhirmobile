import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:worthbang/services/pc_scene.dart';
import 'package:worthbang/services/wglb.dart';

/// Part uji: satu segitiga.
ScenePart _triPart(String role, {int colorArgb = 0xFF8899AA}) => ScenePart(
      role: role,
      positions: Float32List.fromList([0, 0, 0, 10, 0, 0, 0, 10, 0]),
      normals: Float32List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1]),
      indices: Uint32List.fromList([0, 1, 2]),
      colorArgb: colorArgb,
    );

void main() {
  group('WGLB', () {
    test('parse header + payload', () {
      final positions = Float32List.fromList([1, 2, 3, 4, 5, 6]);
      final normals = Float32List.fromList([0, 1, 0, 0, 1, 0]);
      final indices = Uint32List.fromList([0, 1, 0]);
      final header = Uint8List(16);
      final dv = ByteData.sublistView(header);
      header.setRange(0, 4, const [0x57, 0x47, 0x4c, 0x42]);
      dv.setUint32(4, 1, Endian.little);
      dv.setUint32(8, 2, Endian.little);
      dv.setUint32(12, 3, Endian.little);

      final bytes = Uint8List(16 + positions.length * 4 * 2 + indices.length * 4)
        ..setRange(0, 16, header)
        ..setRange(16, 16 + positions.length * 4, positions.buffer.asUint8List())
        ..setRange(
          16 + positions.length * 4,
          16 + positions.length * 8,
          normals.buffer.asUint8List(),
        )
        ..setRange(
          16 + positions.length * 8,
          16 + positions.length * 8 + indices.length * 4,
          indices.buffer.asUint8List(),
        );

      final part = WglbPart.parse(bytes);
      expect(part.vertexCount, 2);
      expect(part.triangleCount, 1);
      expect(part.positions[3], 4);
      expect(part.normals[1], 1);
      expect(part.indices[2], 0);
    });

    test('parse menolak magic salah', () {
      expect(
        () => WglbPart.parse(Uint8List(32)),
        throwsA(isA<FormatException>()),
      );
    });

    test('parse menolak file terpotong', () {
      final header = Uint8List(16);
      final dv = ByteData.sublistView(header);
      header.setRange(0, 4, const [0x57, 0x47, 0x4c, 0x42]);
      dv.setUint32(4, 1, Endian.little);
      dv.setUint32(8, 100, Endian.little);
      dv.setUint32(12, 100, Endian.little);
      expect(
        () => WglbPart.parse(header),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('PcScene.toGlb', () {
    test('menghasilkan GLB valid yang bisa dibaca parser', () {
      final glb = PcScene.toGlb([_triPart('mobo'), _triPart('gpu')]);
      final view = ByteData.sublistView(glb);
      expect(view.getUint32(0, Endian.little), 0x46546C67); // 'glTF'
      expect(view.getUint32(4, Endian.little), 2);
      expect(view.getUint32(8, Endian.little), glb.length);

      // Chunk JSON + chunk BIN.
      final jsonLen = view.getUint32(12, Endian.little);
      expect(view.getUint32(16, Endian.little), 0x4E4F534A);
      final json = jsonDecode(
        utf8.decode(glb.sublist(20, 20 + jsonLen)),
      ) as Map<String, dynamic>;

      expect((json['meshes'] as List).length, 1);
      final prims =
          (json['meshes'] as List)[0]['primitives'] as List;
      expect(prims.length, 2, reason: 'satu primitif per part');
      expect((json['materials'] as List).length, 2);
      expect((json['accessors'] as List).length, 6);

      // Buffer binary: per part 36B posisi + 36B normal + 12B indeks.
      final binHeader = 20 + jsonLen;
      final binLen = view.getUint32(binHeader, Endian.little);
      expect(view.getUint32(binHeader + 4, Endian.little), 0x004E4942);
      expect(binLen, 2 * (36 + 36 + 12));
    });

    test('accessor POSITION punya min/max yang benar', () {
      final glb = PcScene.toGlb([_triPart('mobo')]);
      final view = ByteData.sublistView(glb);
      final jsonLen = view.getUint32(12, Endian.little);
      final json = jsonDecode(
        utf8.decode(glb.sublist(20, 20 + jsonLen)),
      ) as Map<String, dynamic>;
      final accessor = (json['accessors'] as List)[0] as Map<String, dynamic>;
      expect(accessor['min'], [0.0, 0.0, 0.0]);
      expect(accessor['max'], [10.0, 10.0, 0.0]);
      expect(accessor['type'], 'VEC3');
      expect(accessor['componentType'], 5126);
    });

    test('warna linear sesuai sRGB', () {
      final part = _triPart('mobo', colorArgb: 0xFF808080);
      final c = part.linearColor;
      expect(c.length, 4);
      expect(c[3], 1.0);
      // 0.5 sRGB -> sekitar 0.214 linear.
      expect(c[0], closeTo(0.214, 0.01));
    });

    test('scene kosong menghasilkan GLB tanpa primitif', () {
      final glb = PcScene.toGlb(const []);
      final view = ByteData.sublistView(glb);
      final jsonLen = view.getUint32(12, Endian.little);
      final json = jsonDecode(
        utf8.decode(glb.sublist(20, 20 + jsonLen)),
      ) as Map<String, dynamic>;
      expect((json['meshes'] as List)[0]['primitives'], isEmpty);
    });
  });
}
