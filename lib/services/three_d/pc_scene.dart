import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:worthbang/services/three_d/wglb.dart';

/// Rakitan PC sebagai satu scene GLB siap tampil.
///
/// Part di-merge jadi satu buffer: satu primitif per part, satu material per
/// part (warna dasar dari katalog). Viewer native (glbview) yang membaca
/// hasilnya, jadi tidak perlu parser GLB di sisi Dart.
///
/// GLB yang dihasilkan sengaja tanpa tekstur dan tanpa Draco: viewer menolak
/// geometri terkompresi, dan tekstur menambah ukuran APK tanpa manfaat pada
/// skala panggung.
class PcScene {
  const PcScene(this.parts);

  /// Part yang composing scene.
  final List<ScenePart> parts;

  int get triangleCount =>
      parts.fold(0, (s, p) => s + p.indices.length ~/ 3);

  int get vertexCount => parts.fold(0, (s, p) => s + p.positions.length ~/ 3);

  static const int _magicGltf = 0x46546C67;
  static const int _chunkJson = 0x4E4F534A;
  static const int _chunkBin = 0x004E4942;

  /// Merakit GLB dari sekumpulan part.
  ///
  /// [parts] sudah diposisikan di ruang dunia yang sama (milimeter) oleh
  /// pipeline offline, jadi merakit di sini hanya menempelkan buffer.
  static Uint8List toGlb(List<ScenePart> parts) {
    final views = <_BufferView>[];
    final bin = BytesBuilder(copy: false);

    for (final part in parts) {
      final posOffset = bin.length;
      bin.add(_pad4(part.positions.buffer.asUint8List()));
      views.add(_BufferView(
        offset: posOffset,
        length: part.positions.length * 4,
      ));

      final nrmOffset = bin.length;
      bin.add(_pad4(part.normals.buffer.asUint8List()));
      views.add(_BufferView(
        offset: nrmOffset,
        length: part.normals.length * 4,
      ));

      final idxOffset = bin.length;
      bin.add(_pad4(part.indices.buffer.asUint8List()));
      views.add(_BufferView(
        offset: idxOffset,
        length: part.indices.length * 4,
      ));
    }

    final binBytes = bin.toBytes();
    final accessors = <Map<String, dynamic>>[];
    final bufferViews = <Map<String, dynamic>>[];
    final primitives = <Map<String, dynamic>>[];
    final materials = <Map<String, dynamic>>[];

    for (var i = 0; i < parts.length; i++) {
      final part = parts[i];
      final posView = i * 3;
      final nrmView = i * 3 + 1;
      final idxView = i * 3 + 2;

      bufferViews.add({
        'buffer': 0,
        'byteOffset': views[posView].offset,
        'byteLength': views[posView].length,
      });
      bufferViews.add({
        'buffer': 0,
        'byteOffset': views[nrmView].offset,
        'byteLength': views[nrmView].length,
      });
      bufferViews.add({
        'buffer': 0,
        'byteOffset': views[idxView].offset,
        'byteLength': views[idxView].length,
      });

      final min = part.min;
      final max = part.max;
      final posAccessor = accessors.length;
      accessors.add({
        'bufferView': posView,
        'componentType': 5126, // float
        'count': part.positions.length ~/ 3,
        'type': 'VEC3',
        'min': [min.x, min.y, min.z],
        'max': [max.x, max.y, max.z],
      });
      accessors.add({
        'bufferView': nrmView,
        'componentType': 5126, // float
        'count': part.normals.length ~/ 3,
        'type': 'VEC3',
      });
      accessors.add({
        'bufferView': idxView,
        'componentType': 5125, // unsigned int
        'count': part.indices.length,
        'type': 'SCALAR',
      });

      materials.add({
        'name': part.role,
        'pbrMetallicRoughness': {
          'baseColorFactor': part.linearColor,
          'metallicFactor': 0.25,
          'roughnessFactor': 0.6,
        },
      });

      primitives.add({
        'attributes': {'POSITION': posAccessor, 'NORMAL': posAccessor + 1},
        'indices': posAccessor + 2,
        'material': materials.length - 1,
        'mode': 4,
      });
    }

    final json = <String, dynamic>{
      'asset': {'version': '2.0', 'generator': 'worthbang-pc-scene'},
      'scene': 0,
      'scenes': [
        {'nodes': [0]}
      ],
      'nodes': [
        {'mesh': 0, 'name': 'pc'}
      ],
      'meshes': [
        {'name': 'pc', 'primitives': primitives}
      ],
      'materials': materials,
      'accessors': accessors,
      'bufferViews': bufferViews,
      'buffers': [
        {'byteLength': binBytes.length}
      ],
    };

    final jsonBytes = _padJson(utf8.encode(jsonEncode(json)));
    final total = 12 + 8 + jsonBytes.length + 8 + binBytes.length;

    final out = Uint8List(total);
    final view = ByteData.sublistView(out);
    view.setUint32(0, _magicGltf, Endian.little);
    view.setUint32(4, 2, Endian.little);
    view.setUint32(8, total, Endian.little);
    view.setUint32(12, jsonBytes.length, Endian.little);
    view.setUint32(16, _chunkJson, Endian.little);
    out.setRange(20, 20 + jsonBytes.length, jsonBytes);
    final binHeader = 20 + jsonBytes.length;
    view.setUint32(binHeader, binBytes.length, Endian.little);
    view.setUint32(binHeader + 4, _chunkBin, Endian.little);
    out.setRange(binHeader + 8, binHeader + 8 + binBytes.length, binBytes);
    return out;
  }

  /// Padding biner: kelipatan 4 byte, diisi nol (allowed untuk chunk BIN).
  static Uint8List _pad4(List<int> src) {
    final rem = src.length % 4;
    if (rem == 0) return Uint8List.fromList(src);
    final out = Uint8List(src.length + (4 - rem));
    out.setRange(0, src.length, src);
    return out;
  }

  /// Padding chunk JSON: kelipatan 4 byte, diisi spasi (spesifikasi glTF
  /// mewajibkan JSON chunk diakhiri spasi, bukan NUL).
  static Uint8List _padJson(List<int> src) {
    final rem = src.length % 4;
    if (rem == 0) return Uint8List.fromList(src);
    final out = Uint8List(src.length + (4 - rem));
    out.setRange(0, src.length, src);
    for (var i = src.length; i < out.length; i++) {
      out[i] = 0x20; // spasi
    }
    return out;
  }
}

/// Satu part dalam scene: geometri + warna.
class ScenePart {
  ScenePart({
    required this.role,
    required this.positions,
    required this.normals,
    required this.indices,
    required this.colorArgb,
  });

  final String role;
  final Float32List positions;
  final Float32List normals;
  final Uint32List indices;
  final int colorArgb;

  /// Bounding box minimum part (millimeter).
  Vec3 get min => Vec3(_minOf(0), _minOf(1), _minOf(2));

  /// Bounding box maksimum part (millimeter).
  Vec3 get max => Vec3(_maxOf(0), _maxOf(1), _maxOf(2));

  double _minOf(int axis) {
    var v = double.infinity;
    for (var i = axis; i < positions.length; i += 3) {
      if (positions[i] < v) v = positions[i];
    }
    return v;
  }

  double _maxOf(int axis) {
    var v = -double.infinity;
    for (var i = axis; i < positions.length; i += 3) {
      if (positions[i] > v) v = positions[i];
    }
    return v;
  }

  /// Warna sRGB dari katalog -> faktor linear glTF.
  List<double> get linearColor {
    final r = ((colorArgb >> 16) & 0xff) / 255.0;
    final g = ((colorArgb >> 8) & 0xff) / 255.0;
    final b = (colorArgb & 0xff) / 255.0;
    double lin(double v) {
      if (v <= 0.04045) return v / 12.92;
      return math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return [lin(r), lin(g), lin(b), 1.0];
  }

  factory ScenePart.fromVariant(WglbVariant variant, WglbPart geometry) =>
      ScenePart(
        role: variant.role,
        positions: geometry.positions,
        normals: geometry.normals,
        indices: geometry.indices,
        colorArgb: variant.colorValue,
      );
}

/// Vektor 3D sederhana untuk bounding box part.
class Vec3 {
  const Vec3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

class _BufferView {
  const _BufferView({required this.offset, required this.length});
  final int offset;
  final int length;
}
