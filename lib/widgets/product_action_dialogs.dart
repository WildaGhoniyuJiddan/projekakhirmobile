import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/dream_strings.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/services/features/alerts_api.dart';
import 'package:worthbang/services/features/dream_build_api.dart';
import 'package:worthbang/services/features/personalization/personalization_engine.dart';

/// Slot Rakitan Impian dari mode + nama/teks produk (heuristik kata kunci).
String dreamSlotFor({required String mode, required String query}) {
  final hay = '$mode $query'.toLowerCase();
  bool has(List<String> keys) => keys.any(hay.contains);
  if (has(['gpu', 'vga', 'rtx', 'gtx', 'radeon', 'geforce'])) return 'GPU';
  if (has(['cpu', 'prosesor', 'processor', 'ryzen'])) return 'CPU';
  if (has(['motherboard', 'mobo', 'mainboard'])) return 'Motherboard';
  if (has(['ram', 'memori', 'memory', 'ddr'])) return 'RAM';
  if (has(['ssd', 'hdd', 'nvme', 'storage', 'harddisk'])) return 'Storage';
  if (has(['psu', 'power supply'])) return 'PSU';
  if (has(['casing', 'case'])) return 'Casing';
  if (has(['cooler', 'pendingin'])) return 'Cooler';
  if (has(['monitor', 'layar'])) return 'Monitor';
  return 'Lainnya';
}

// Event personalisasi (AI-Core): produk masuk Rakitan Impian adalah
// sinyal terkuat (bobot 5). Kategori sengaja tidak diisi — label slot
// ("CPU"/"Lainnya") beda kosakata dengan kategori katalog; mesin
// mendeteksi kategori dari nama produk. Best-effort: kegagalan
// mencatat tidak boleh mengganggu alur utama.
Future<void> _recordAddToDreamEvent(String partName, int price) async {
  try {
    final engine =
        PersonalizationEngine(await SharedPreferences.getInstance());
    await engine.record(UserEvent(
      type: UserEventType.addToDream,
      productName: partName,
      price: price,
      at: DateTime.now(),
    ));
  } catch (_) {
    // Telemetri personalisasi gagal = diam saja.
  }
}

/// Dialog tambah produk ke kartu Rakitan Impian:
/// pilih kartu yang ada atau buat baru.
Future<void> showDreamBuildDialog(
  BuildContext context,
  WidgetRef ref, {
  required String partName,
  required int price,
  required String slot,
}) async {
  final api = ref.read(dreamBuildApiProvider);
  List<DreamBuild> builds;
  try {
    builds = await api.listBuilds();
  } catch (e) {
    if (context.mounted) {
      showMonexToast(context, e.toString(), isError: true);
    }
    return;
  }
  if (!context.mounted) return;
  final picked = await showDialog<DreamBuild?>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(DreamStrings.addFromResultTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final b in builds)
              ListTile(
                title: Text(b.name),
                subtitle: Text(
                  '${b.isPublished ? DreamStrings.statusPublished : DreamStrings.statusDraft}'
                  ' • ${DreamStrings.versionLabel} ${b.version}',
                ),
                onTap: () => Navigator.of(context).pop(b),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text(DreamStrings.addFromResultNew),
              onTap: () => Navigator.of(context).pop(null),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  try {
    final item = DreamBuildItem(
      slot: slot,
      partName: partName,
      price: price,
    );
    final DreamBuild target;
    if (picked == null) {
      target = await api.createBuild(partName);
      await api.saveDraft(
        build: target,
        name: target.name,
        items: [item],
      );
    } else {
      target = picked;
      await api.saveDraft(
        build: target,
        name: target.name,
        items: [...target.items, item],
      );
    }
    _recordAddToDreamEvent(partName, price);
    if (context.mounted) {
      showMonexToast(context, DreamStrings.addedToast, isSuccess: true);
    }
  } catch (e) {
    if (context.mounted) {
      showMonexToast(context, e.toString(), isError: true);
    }
  }
}

/// Dialog buat price alert: input target harga → simpan lokal.
Future<void> showPriceAlertDialog(
  BuildContext context,
  WidgetRef ref, {
  required String query,
  required String mode,
  required int initialTargetPrice,
}) async {
  final target = TextEditingController(text: initialTargetPrice.toString());
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(AppStrings.addAlert),
      content: TextField(
        controller: target,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: AppStrings.targetPriceLabel,
          prefixText: 'Rp ',
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStrings.cancelButton),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(AppStrings.saveButton),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final price =
      int.tryParse(target.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  if (price <= 0) return;
  try {
    await ref.read(alertsApiProvider).addAlert(
          query: query,
          mode: mode,
          targetPrice: price,
        );
    if (context.mounted) {
      showMonexToast(context, AppStrings.alertAdded, isSuccess: true);
    }
  } catch (e) {
    if (context.mounted) {
      showMonexToast(context, e.toString(), isError: true);
    }
  }
}
