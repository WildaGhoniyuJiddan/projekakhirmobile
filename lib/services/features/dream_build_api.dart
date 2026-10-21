import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final dreamBuildApiProvider = Provider<DreamBuildApi>(
  (_) => DreamBuildApi(),
);

/// Urutan slot TETAP untuk teks kanonik & editor (spek WB-DREAM-v1).
const List<String> dreamSlots = [
  'CPU',
  'Motherboard',
  'GPU',
  'RAM',
  'Storage',
  'PSU',
  'Casing',
  'Cooler',
  'Monitor',
  'Lainnya',
];

int dreamSlotIndex(String slot) {
  final i = dreamSlots.indexOf(slot);
  return i < 0 ? dreamSlots.length : i;
}

/// Satu part terisi pada kartu Rakitan Impian.
class DreamBuildItem {
  const DreamBuildItem({
    this.id,
    required this.slot,
    required this.partName,
    required this.price,
    this.sort = 0,
  });

  final int? id;
  final String slot;
  final String partName;
  final int price;
  final int sort;

  factory DreamBuildItem.fromJson(Map<String, dynamic> json) =>
      DreamBuildItem(
        id: (json['id'] as num?)?.toInt(),
        slot: json['slot'] as String? ?? 'Lainnya',
        partName: json['part_name'] as String? ?? '',
        price: (json['price'] as num? ?? 0).toInt(),
        sort: (json['sort'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toInsert(String buildId) => {
        'build_id': buildId,
        'slot': slot,
        'part_name': partName,
        'price': price,
        'sort': sort,
      };
}

/// Kartu Rakitan Impian (draft di Supabase; terbit = hash tercatat
/// on-chain lewat Edge Function `publish-build`).
class DreamBuild {
  const DreamBuild({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.version,
    required this.status,
    this.contentHash,
    this.txHash,
    this.publishedVersion,
    this.publishedAt,
    this.items = const [],
  });

  final String id;
  final String ownerId;
  final String name;
  final int version;
  final String status; // 'draft' | 'published'
  final String? contentHash;
  final String? txHash;
  final int? publishedVersion;
  final DateTime? publishedAt;
  final List<DreamBuildItem> items;

  bool get isPublished => status == 'published';

  int get total => items.fold(0, (sum, it) => sum + it.price);

  factory DreamBuild.fromJson(Map<String, dynamic> json) {
    final rawItems = json['dream_build_items'];
    return DreamBuild(
      id: json['id'] as String? ?? '',
      ownerId: json['owner_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      version: (json['version'] as num? ?? 1).toInt(),
      status: json['status'] as String? ?? 'draft',
      contentHash: json['content_hash'] as String?,
      txHash: json['tx_hash'] as String?,
      publishedVersion: (json['published_version'] as num?)?.toInt(),
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      items: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(DreamBuildItem.fromJson)
              .toList()
          : const [],
    );
  }
}

/// Susun teks kanonik WB-DREAM-v1 (kontrak bersama Dart/TS/Solidity —
/// lihat contracts/README.md). Item diurutkan per urutan slot tetap,
/// lalu `sort`. TANPA newline di akhir.
String dreamCanonicalText({
  required String cardId,
  required String ownerId,
  required int version,
  required List<DreamBuildItem> items,
}) {
  final sorted = [...items]..sort((a, b) {
      final bySlot = dreamSlotIndex(a.slot).compareTo(dreamSlotIndex(b.slot));
      return bySlot != 0 ? bySlot : a.sort.compareTo(b.sort);
    });
  final total = sorted.fold(0, (sum, it) => sum + it.price);
  final lines = <String>[
    'WB-DREAM-v1',
    'card:$cardId',
    'owner:$ownerId',
    'version:$version',
    for (final it in sorted)
      'slot=${it.slot};name=${it.partName};price=${it.price}',
    'total=$total',
  ];
  return lines.join('\n');
}

/// contentHash kartu: SHA-256 hex lowercase dari teks kanonik.
String dreamContentHash({
  required String cardId,
  required String ownerId,
  required int version,
  required List<DreamBuildItem> items,
}) =>
    sha256
        .convert(utf8.encode(dreamCanonicalText(
          cardId: cardId,
          ownerId: ownerId,
          version: version,
          items: items,
        )))
        .toString();

/// cardId on-chain (bytes32): SHA-256 dari string uuid kartu.
String dreamCardIdBytes32(String cardId) =>
    sha256.convert(utf8.encode(cardId)).toString();

/// CRUD draft Rakitan Impian di Supabase (pola API fitur lain: provider
/// Riverpod + model fromJson). RLS menjamin user hanya menyentuh
/// kartunya sendiri.
class DreamBuildApi {
  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseClient get _requireClient {
    final c = _client;
    if (c == null) throw StateError('Supabase belum diinisialisasi');
    return c;
  }

  static const _select = '*, dream_build_items(*)';

  Future<List<DreamBuild>> listBuilds() async {
    final client = _client;
    if (client == null) return const [];
    final rows = await client
        .from('dream_builds')
        .select(_select)
        .order('updated_at', ascending: false);
    return (rows as List)
        .whereType<Map<String, dynamic>>()
        .map(DreamBuild.fromJson)
        .toList();
  }

  Future<DreamBuild> getBuild(String id) async {
    final row = await _requireClient
        .from('dream_builds')
        .select(_select)
        .eq('id', id)
        .single();
    return DreamBuild.fromJson(row);
  }

  Future<DreamBuild> createBuild(String name) async {
    final client = _requireClient;
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Belum login');
    final row = await client
        .from('dream_builds')
        .insert({'owner_id': user.id, 'name': name})
        .select(_select)
        .single();
    return DreamBuild.fromJson(row);
  }

  /// Simpan draft (nama + seluruh isi). Mengedit kartu yang sudah
  /// terbit menaikkan version dan mengembalikan status ke 'draft';
  /// catatan penerbitan terakhir (content_hash/tx_hash/published_*)
  /// TIDAK dihapus.
  Future<DreamBuild> saveDraft({
    required DreamBuild build,
    required String name,
    required List<DreamBuildItem> items,
  }) async {
    final client = _requireClient;
    final wasPublished = build.isPublished;
    await client.from('dream_builds').update({
      'name': name,
      if (wasPublished) 'version': build.version + 1,
      if (wasPublished) 'status': 'draft',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', build.id);
    await client.from('dream_build_items').delete().eq('build_id', build.id);
    if (items.isNotEmpty) {
      final sorted = [...items]..sort((a, b) {
          final bySlot =
              dreamSlotIndex(a.slot).compareTo(dreamSlotIndex(b.slot));
          return bySlot != 0 ? bySlot : a.sort.compareTo(b.sort);
        });
      await client.from('dream_build_items').insert([
        for (var i = 0; i < sorted.length; i++)
          DreamBuildItem(
            slot: sorted[i].slot,
            partName: sorted[i].partName,
            price: sorted[i].price,
            sort: i,
          ).toInsert(build.id),
      ]);
    }
    return getBuild(build.id);
  }

  Future<void> deleteBuild(String id) async {
    await _requireClient.from('dream_builds').delete().eq('id', id);
  }

  /// Terbitkan: Edge Function menyusun ulang teks kanonik dari DB,
  /// menghitung hash di server, dan mencatatnya on-chain. Kartu dimuat
  /// ulang sesudahnya (status/tx_hash dari server).
  Future<DreamBuild> publish(String buildId) async {
    final client = _requireClient;
    final res = await client.functions.invoke(
      'publish-build',
      body: {'build_id': buildId},
    );
    if (res.status != 200) {
      throw StateError('Publish gagal (HTTP ${res.status}): ${res.data}');
    }
    return getBuild(buildId);
  }
}
