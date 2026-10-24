import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:worthbang/config/supabase_config.dart';
import 'package:worthbang/l10n/dream_strings.dart';
import 'package:worthbang/services/data/local_catalog.dart';
import 'package:worthbang/services/features/dream_build_api.dart';
import 'package:worthbang/utils/rupiah.dart';

/// URL halaman verifikasi publik kartu (Edge Function verify-build).
String dreamVerifyUrl(String buildId) =>
    '$supabaseUrl/functions/v1/verify-build?id=$buildId';

/// Daftar kartu Rakitan Impian + buat baru.
class DreamBuildScreen extends ConsumerStatefulWidget {
  const DreamBuildScreen({super.key});

  @override
  ConsumerState<DreamBuildScreen> createState() => _DreamBuildScreenState();
}

class _DreamBuildScreenState extends ConsumerState<DreamBuildScreen> {
  late Future<List<DreamBuild>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(dreamBuildApiProvider).listBuilds();
  }

  void _reload() {
    setState(() {
      _future = ref.read(dreamBuildApiProvider).listBuilds();
    });
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(DreamStrings.newBuild),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: DreamStrings.nameLabel,
            hintText: DreamStrings.nameHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(DreamStrings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(DreamStrings.create),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      final build = await ref.read(dreamBuildApiProvider).createBuild(name);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DreamBuildEditor(build: build)),
      );
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(DreamStrings.title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text(DreamStrings.newBuild),
      ),
      body: FutureBuilder<List<DreamBuild>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(snap.error.toString()));
          }
          final builds = snap.data ?? const [];
          if (builds.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(DreamStrings.empty, textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: builds.length,
            itemBuilder: (context, i) {
              final b = builds[i];
              return Card(
                child: ListTile(
                  title: Text(b.name),
                  subtitle: Text(
                    '${b.isPublished ? DreamStrings.statusPublished : DreamStrings.statusDraft}'
                    ' • ${DreamStrings.versionLabel} ${b.version}'
                    ' • ${DreamStrings.totalLabel}: ${formatRupiah(b.total)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DreamBuildEditor(build: b),
                      ),
                    );
                    _reload();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Editor + detail satu kartu: nama, isi per slot, simpan draft,
/// terbitkan (tx hash + QR verifikasi).
class DreamBuildEditor extends ConsumerStatefulWidget {
  const DreamBuildEditor({super.key, required this.build});

  final DreamBuild build;

  @override
  ConsumerState<DreamBuildEditor> createState() => _DreamBuildEditorState();
}

class _DreamBuildEditorState extends ConsumerState<DreamBuildEditor> {
  late DreamBuild _build;
  late final TextEditingController _nameCtrl;
  late final Map<String, DreamBuildItem?> _slots;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _build = widget.build;
    _nameCtrl = TextEditingController(text: _build.name);
    _slots = {
      for (final slot in dreamSlots) slot: null,
      for (final it in _build.items) it.slot: it,
    };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  List<DreamBuildItem> get _items => [
        for (final e in _slots.entries)
          if (e.value != null) e.value!,
      ];

  int get _total => _items.fold(0, (s, it) => s + it.price);

  Future<void> _pickPart(String slot) async {
    final catalog = await LocalCatalog.load();
    if (!mounted) return;
    const categoryOf = {
      'CPU': 'cpu',
      'Motherboard': 'motherboard',
      'GPU': 'gpu',
      'RAM': 'ram',
      'Storage': 'storage',
      'PSU': 'psu',
      'Casing': 'case',
    };
    final key = categoryOf[slot];
    final pool = key != null
        ? (catalog[key] ?? const <CatalogItem>[])
        : catalog.values.expand((l) => l).toList();
    final picked = await showModalBottomSheet<CatalogItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final shown = pool
                .where((e) =>
                    query.isEmpty ||
                    e.model.toLowerCase().contains(query.toLowerCase()))
                .take(100)
                .toList();
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.75,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: DreamStrings.searchPartHint,
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (context, i) => ListTile(
                          title: Text(shown[i].model),
                          trailing: Text(formatRupiah(shown[i].price)),
                          onTap: () => Navigator.of(context).pop(shown[i]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _slots[slot] = DreamBuildItem(
        slot: slot,
        partName: picked.model,
        price: picked.price,
      );
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(dreamBuildApiProvider).saveDraft(
            build: _build,
            name: _nameCtrl.text.trim().isEmpty
                ? _build.name
                : _nameCtrl.text.trim(),
            items: _items,
          );
      if (!mounted) return;
      setState(() => _build = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(DreamStrings.savedToast)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _publish() async {
    setState(() => _busy = true);
    try {
      // Pastikan isi terbaru tersimpan dulu sebelum diterbitkan.
      await _save();
      if (!mounted) return;
      final published =
          await ref.read(dreamBuildApiProvider).publish(_build.id);
      if (!mounted) return;
      setState(() => _build = published);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(DreamStrings.publishedToast)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    try {
      await ref.read(dreamBuildApiProvider).deleteBuild(_build.id);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(DreamStrings.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: DreamStrings.nameLabel,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${_build.isPublished ? DreamStrings.statusPublished : DreamStrings.statusDraft}'
            ' • ${DreamStrings.versionLabel} ${_build.version}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final slot in dreamSlots)
            Card(
              child: ListTile(
                title: Text(slot),
                subtitle: Text(
                  _slots[slot] == null
                      ? DreamStrings.emptySlot
                      : '${_slots[slot]!.partName}\n'
                          '${formatRupiah(_slots[slot]!.price)}',
                ),
                isThreeLine: _slots[slot] != null,
                trailing: _slots[slot] == null
                    ? const Icon(Icons.add)
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: DreamStrings.clearSlot,
                        onPressed: () => setState(() => _slots[slot] = null),
                      ),
                onTap: () => _pickPart(slot),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '${DreamStrings.totalLabel}: ${formatRupiah(_total)}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text(DreamStrings.saveDraft),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy ? null : _publish,
            icon: const Icon(Icons.link),
            label: Text(
              _busy ? DreamStrings.publishing : DreamStrings.publish,
            ),
          ),
          if (_build.isPublished && _build.txHash != null) ...[
            const SizedBox(height: 24),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.verified, color: Colors.green, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${DreamStrings.txHashLabel} (Polygon Amoy)',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _build.txHash!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: _build.txHash!),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(DreamStrings.txHashCopiedToast),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text(DreamStrings.copyTxHash),
                    ),
                    if (_build.contentHash != null) ...[
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.tag, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              DreamStrings.contentHashLabel,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          IconButton(
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            tooltip: DreamStrings.copyContentHash,
                            icon: const Icon(Icons.copy),
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _build.contentHash!),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      DreamStrings.contentHashCopiedToast,
                                    ),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        _build.contentHash!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: QrImageView(
                data: dreamVerifyUrl(_build.id),
                size: 180,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Center(child: Text(DreamStrings.verifyQrLabel)),
          ],
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
            label: const Text(DreamStrings.delete),
          ),
        ],
      ),
    );
  }
}
