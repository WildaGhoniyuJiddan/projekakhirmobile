// Verifikasi output optimizer terhadap parser resmi `glbview` (Dart).
//
// Parser di sini persis sama yang dipakai app saat runtime, jadi file yang
// lolos test ini pasti bisa dirender.
//
// Test 2 membandingkan jumlah triangle output dengan sumber. Sumber dibaca
// lewat laporan JSON yang dihasilkan optimizer (Node), karena beberapa file
// sumber ber-Draco — parser `glbview` memang menolak Draco, dan itu
//	batasan renderer, bukan cacat file sumber.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:glbview/glbview.dart';

/// Jumlah file .glb di bawah [dir], rekursif.
List<File> glbFilesIn(Directory dir) {
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.glb'))
      .toList();
}

void main() {
  test('parser glbview menerima semua hasil optimasi', () {
    final files = glbFilesIn(Directory('tool/output/optimized'));
    expect(files, isNotEmpty, reason: 'tool/output/optimized/ kosong — jalankan optimizer dulu');

    final failures = <String>[];
    for (final f in files) {
      try {
        final model = parseGlb(Uint8List.fromList(f.readAsBytesSync()));
        if (model.primitives.isEmpty) {
          failures.add('${f.path}: tidak ada primitive');
        }
      } catch (e) {
        failures.add('${f.path}: $e');
      }
    }
    expect(failures, isEmpty, reason: 'parser glbview menolak:\n${failures.join('\n')}');
  });

  test('jumlah triangle output identik dengan sumber (tidak ada poligon hilang)', () {
    final reportFile = File('tool/output/optimized/optimize_report.json');
    expect(reportFile.existsSync(), isTrue, reason: 'laporan optimizer tidak ada');

    final report = jsonDecode(reportFile.readAsStringSync()) as Map<String, dynamic>;
    final files = (report['files'] as List).cast<Map<String, dynamic>>();
    expect(files, isNotEmpty, reason: 'laporan optimizer kosong');

    for (final entry in files) {
      final rel = entry['rel'] as String;
      final outName = entry['out'] as String;
      final tris = entry['tris'] as num;

      // Output harus ada dan bisa di-parse.
      final out = File('tool/output/optimized${Platform.pathSeparator}$outName');
      expect(out.existsSync(), isTrue, reason: 'output hilang: $outName');

      final model = parseGlb(Uint8List.fromList(out.readAsBytesSync()));
      final triParsed = model.primitives.fold<int>(
        0,
        (s, p) => s + p.indices.length ~/ 3,
      );

      expect(
        triParsed,
        tris.toInt(),
        reason: 'triangle output != laporan optimizer di $rel',
      );
    }
  });

  test('tiada file output yang memakai Draco atau meshopt', () {
    final files = glbFilesIn(Directory('tool/output/optimized'));
    final offenders = <String>[];

    for (final f in files) {
      final bytes = f.readAsBytesSync();
      // GLB: 12 byte header, lalu chunk. JSON chunk dimulai di offset 20.
      final jsonLength = ByteData.sublistView(bytes).getUint32(12, Endian.little);
      final json = jsonDecode(
        utf8.decode(bytes.sublist(20, 20 + jsonLength)),
      ) as Map<String, dynamic>;

      final used = (json['extensionsUsed'] as List?)?.cast<String>() ?? const [];
      final required =
          (json['extensionsRequired'] as List?)?.cast<String>() ?? const [];
      final all = {...used, ...required};

      if (all.any((e) => e.contains('draco') || e.contains('meshopt'))) {
        offenders.add('${f.path}: ${all.join(', ')}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'glbview menolak Draco/meshopt:\n${offenders.join('\n')}',
    );
  });
}
