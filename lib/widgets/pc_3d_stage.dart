import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:glbview/glbview.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/pc_scene.dart';
import 'package:worthbang/services/wglb.dart';

/// Panggung 3D untuk fitur Rakit PC Acak.
///
/// Prinsip:
///  - Isolasi: panggung berdiri sendiri di dalam box-nya. Gesture kamera
///    hanya rotate horizontal, jadi drag vertikal tetap milik list di atasnya.
///  - Lifecycle: viewer native dispose saat widget dilepas; cache GPU
///    dilepas saat tidak ada yang memakainya.
///  - Reactive: state UI (build, budget, status) datang dari luar lewat
///    [parts]; loop animasi 3D berjalan di dalam viewer native, jadi
///    perubahan state tidak memicu rebuild seluruh widget.
class Pc3DStage extends StatefulWidget {
  const Pc3DStage({
    super.key,
    required this.parts,
    this.height = 260,
    this.loading = false,
    this.label,
  });

  /// Part yang ditampilkan. Kosong -> tampil fallback 2D.
  final List<WglbVariant> parts;

  final double height;

  /// True saat proses merakit scene berjalan: panggung menampilkan loader.
  final bool loading;

  /// Nama build yang sedang ditampilkan.
  final String? label;

  @override
  State<Pc3DStage> createState() => _Pc3DStageState();
}

class _Pc3DStageState extends State<Pc3DStage> {
  /// GLB hasil rakitan; null sebelum scene selesai dirakit.
  Uint8List? _glb;

  /// Kunci cache model di plugin: scene yang sama tidak di-upload dua kali.
  String? _cacheKey;

  Object? _error;

  /// Epoch: naik setiap permintaan scene baru; hasil lama diabaikan.
  int _epoch = 0;

  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced != _reducedMotion) {
      _reducedMotion = reduced;
      if (mounted) setState(() {});
    }
  }

  @override
  void didUpdateWidget(Pc3DStage old) {
    super.didUpdateWidget(old);
    if (!identical(old.parts, widget.parts)) _sync();
  }

  @override
  void dispose() {
    _epoch++;
    // Model yang sedang tampil dilepas oleh viewer; sisanya di-evict agar
    // GPU tidak menahan mesh yang tidak dipakai.
    _cacheKey = null;
    super.dispose();
  }

  /// Merakit scene di isolate terpisah lalu mengunggah ke GPU.
  Future<void> _sync() async {
    final parts = widget.parts;
    if (parts.isEmpty) {
      if (mounted) {
        setState(() {
          _glb = null;
          _cacheKey = null;
          _error = null;
        });
      }
      return;
    }
    final epoch = ++_epoch;
    try {
      final glb = await assembleScene(parts);
      if (!mounted || epoch != _epoch) return;
      final key = 'pc-scene-${parts.map((p) => p.id).join('-')}';
      await GlbView.precacheMemory(glb, cacheKey: key);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _glb = glb;
        _cacheKey = key;
        _error = null;
      });
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final glb = _glb;
    final error = _error;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MonexSpacing.radiusCard),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).colorScheme.surface,
                Theme.of(context).colorScheme.surfaceContainerHighest,
              ],
            ),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (error != null)
                const _Fallback2D(
                  message: '3D tidak tersedia',
                  icon: Icons.view_in_ar_outlined,
                )
              else if (glb == null)
                _Fallback2D(
                  message: widget.loading ? 'Menyusun rakitan…' : 'Menyiapkan model 3D',
                  icon: Icons.memory_rounded,
                  busy: widget.loading,
                )
              else
                _Viewer(
                  bytes: glb,
                  cacheKey: _cacheKey,
                  reducedMotion: _reducedMotion,
                ),
              if (widget.label != null)
                Positioned(
                  left: 12,
                  bottom: 12,
                  right: 12,
                  child: _StageCaption(label: widget.label!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Viewer native. Auto-rotate dimatikan saat reduced motion aktif.
class _Viewer extends StatelessWidget {
  const _Viewer({
    required this.bytes,
    required this.cacheKey,
    required this.reducedMotion,
  });

  final Uint8List bytes;
  final String? cacheKey;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 260.0;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: GlbView.memory(
              bytes,
              cacheKey: cacheKey,
              width: width,
              height: height,
              autoRotate: !reducedMotion,
              autoRotateDegreesPerSecond: 18,
              // Hanya drag horizontal yang dipakai kamera; drag vertikal tetap
              // milik scroll list di atasnya.
              gestures: const {GlbGesture.rotate},
              placeholder: const _Fallback2D(
                message: 'Memuat model…',
                icon: Icons.memory_rounded,
                busy: true,
              ),
              errorBuilder: (context, error) => const _Fallback2D(
                message: 'WebGL tidak tersedia',
                icon: Icons.warning_amber_rounded,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Fallback 2D: dipakai saat WebGL gagal atau model tidak bisa dimuat.
class _Fallback2D extends StatelessWidget {
  const _Fallback2D({
    required this.message,
    required this.icon,
    this.busy = false,
  });

  final String message;
  final IconData icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const MonexOrbitLoader(size: 34)
          else
            Icon(icon,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 30),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _StageCaption extends StatelessWidget {
  const _StageCaption({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(MonexSpacing.radiusSm),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.view_in_ar, size: 14, color: MonexColors.lime),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Merakit scene dari daftar varian.
///
/// Aset dibaca di isolate utama, lalu scene dirakit di isolate terpisah
/// supaya parsing geometri tidak memblokir frame UI.
Future<Uint8List> assembleScene(List<WglbVariant> parts) async {
  final payloads = <String, Uint8List>{};
  for (final variant in parts) {
    final data = await rootBundle.load(variant.file);
    payloads[variant.file] = data.buffer.asUint8List();
  }
  return Isolate.run(() {
    final sceneParts = <ScenePart>[];
    for (final variant in parts) {
      final geometry = WglbPart.parse(payloads[variant.file]!);
      sceneParts.add(ScenePart.fromVariant(variant, geometry));
    }
    return PcScene.toGlb(sceneParts);
  });
}
