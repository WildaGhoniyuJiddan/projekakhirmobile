import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Satu part 3D: posisi + normal (Float32) dan indeks (Uint32).
///
/// Format file `.wglb` (dipakai tool/prepare_3d.mjs):
/// ```
/// offset 0  : 4 byte  magic 'WGLB'
/// offset 4  : u32     version (1)
/// offset 8  : u32     vertexCount
/// offset 12 : u32     indexCount
/// offset 16 : f32[]   positions  (x,y,z per vertex)
///              f32[]   normals   (x,y,z per vertex)
///              u32[]   indices
/// ```
class WglbPart {
  WglbPart({
    required this.positions,
    required this.normals,
    required this.indices,
  });

  final Float32List positions;
  final Float32List normals;
  final Uint32List indices;

  int get vertexCount => positions.length ~/ 3;
  int get triangleCount => indices.length ~/ 3;

  static const int _headerSize = 16;
  static const int _magicW = 0x57;
  static const int _magicG = 0x47;
  static const int _magicL = 0x4c;
  static const int _magicB = 0x42;

  /// Membaca part dari bundle aset. Format salah melempar [FormatException].
  static WglbPart parse(Uint8List bytes) {
    if (bytes.length < _headerSize) {
      throw const FormatException('WGLB terlalu pendek');
    }
    final view = ByteData.sublistView(bytes);
    if (view.getUint8(0) != _magicW ||
        view.getUint8(1) != _magicG ||
        view.getUint8(2) != _magicL ||
        view.getUint8(3) != _magicB) {
      throw const FormatException('Magic WGLB tidak cocok');
    }
    final version = view.getUint32(4, Endian.little);
    if (version != 1) {
      throw FormatException('Versi WGLB tidak didukung: $version');
    }
    final vertexCount = view.getUint32(8, Endian.little);
    final indexCount = view.getUint32(12, Endian.little);

    final posBytes = vertexCount * 3 * 4;
    final normBytes = posBytes;
    final idxBytes = indexCount * 4;
    final needed = _headerSize + posBytes + normBytes + idxBytes;
    if (bytes.length < needed) {
      throw FormatException(
        'WGLB terpotong: butuh $needed byte, ada ${bytes.length}',
      );
    }

    var offset = _headerSize;
    final positions = Float32List.sublistView(
      bytes, offset, offset + posBytes,
    );
    offset += posBytes;
    final normals = Float32List.sublistView(
      bytes, offset, offset + normBytes,
    );
    offset += normBytes;
    final indices = Uint32List.sublistView(bytes, offset, offset + idxBytes);

    return WglbPart(
      positions: Float32List.fromList(positions),
      normals: Float32List.fromList(normals),
      indices: Uint32List.fromList(indices),
    );
  }

  static Future<WglbPart> load(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return parse(data.buffer.asUint8List());
  }
}

/// Metadata satu varian part dari `assets/3d/prepared/catalog.json`.
class WglbVariant {
  const WglbVariant({
    required this.id,
    required this.role,
    required this.name,
    required this.file,
    required this.colorValue,
    required this.triangleCount,
  });

  final String id;
  final String role;
  final String name;
  final String file;

  /// Warna dasar part (ARGB), dipakai untuk mewarnai mesh.
  final int colorValue;

  final int triangleCount;

  static WglbVariant fromJson(Map<String, dynamic> json) => WglbVariant(
        id: json['id'] as String,
        role: json['role'] as String,
        name: json['name'] as String? ?? '-',
        file: json['file'] as String,
        colorValue: _parseHex(json['color'] as String? ?? '#8899AA'),
        triangleCount: (json['tris'] as num?)?.toInt() ?? 0,
      );

  static int _parseHex(String hex) {
    var h = hex.replaceAll('#', '');
    if (h.length == 6) h = 'ff$h';
    final v = int.tryParse(h, radix: 16) ?? 0xFF8899AA;
    return v;
  }
}

/// Satu set PC utuh dari catalog.json v2: semua part dari satu build
/// BuildCores. Part-partnya sudah saling pas di frame yang sama —
/// tampilkan selalu sebagai satu kesatuan, jangan dicampur antar set.
class WglbSet {
  const WglbSet({required this.id, required this.name, required this.parts});

  final String id;
  final String name;
  final List<WglbVariant> parts;

  static WglbSet fromJson(Map<String, dynamic> json) => WglbSet(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['id'] as String,
        parts: [
          for (final e in (json['parts'] as List? ?? const []))
            if (e is Map<String, dynamic>) WglbVariant.fromJson(e),
        ],
      );
}

/// Katalog 3D v2: daftar set PC utuh. Yang diacak di UI adalah set-nya;
/// model murni hiasan dan tidak mewakili komponen hasil build acak.
class WglbCatalog {
  WglbCatalog(this.sets);

  final List<WglbSet> sets;

  static WglbCatalog? _cached;

  static const String catalogAsset = 'assets/3d/prepared/catalog.json';

  static Future<WglbCatalog> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(catalogAsset);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final sets = <WglbSet>[
      for (final e in (decoded['sets'] as List? ?? const []))
        if (e is Map<String, dynamic>) WglbSet.fromJson(e),
    ];
    final catalog = WglbCatalog(sets);
    _cached = catalog;
    return catalog;
  }

  bool get isEmpty => sets.isEmpty;

  /// Total triangle seluruh set — dipakai untuk budget APK.
  int get totalTriangles => sets
      .expand((s) => s.parts)
      .fold(0, (s, v) => s + v.triangleCount);
}
