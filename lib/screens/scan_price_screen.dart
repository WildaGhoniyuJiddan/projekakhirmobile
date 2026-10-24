import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/utils/rupiah.dart';

import '../services/features/scan_price_parser.dart';
import '../services/features/scan_price_service.dart';

enum ScanScreenState { guide, loading, confirm, error }

/// Layar Pindai Harga: foto label harga di toko -> OCR on-device (ML Kit,
/// bukan LLM) -> konfirmasi sekali ketuk -> analyze() yang sama dengan
/// layar Cek Harga -> ResultScreen. Tanpa percakapan, tanpa Dodo.
class ScanPriceScreen extends StatefulWidget {
  final IScanPriceService scanService;

  /// Callback untuk meneruskan (query, price) ke PriceCheckApi.analyze()
  /// -> ResultScreen. Diimplementasikan di titik pemanggil.
  final Future<void> Function(BuildContext context, String query, int price)
  onAnalyzeRequested;

  /// Callback untuk mengarahkan user ke form Cek Harga manual jika gagal total.
  final void Function(BuildContext context, {String? initialQuery})
  onFallbackManual;

  const ScanPriceScreen({
    super.key,
    required this.scanService,
    required this.onAnalyzeRequested,
    required this.onFallbackManual,
  });

  @override
  State<ScanPriceScreen> createState() => _ScanPriceScreenState();
}

class _ScanPriceScreenState extends State<ScanPriceScreen> {
  final _formKey = GlobalKey<FormState>();
  ScanScreenState _state = ScanScreenState.guide;
  ScanParseResult? _parseResult;
  String? _errorMessage;
  bool _isSubmittingAnalyze = false;

  late final TextEditingController _queryController;
  late final TextEditingController _priceController;
  int? _selectedChipPrice;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _priceController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _priceController.dispose();
    widget.scanService.dispose();
    super.dispose();
  }

  int? _parsePrice(String raw) {
    final digits = int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), ''));
    return (digits == null || digits <= 0) ? null : digits;
  }

  Future<void> _handlePickImage(ImageSource source) async {
    setState(() {
      _state = ScanScreenState.loading;
      _errorMessage = null;
    });

    final result = await widget.scanService.captureAndParse(source: source);
    if (!mounted) return;

    if (result.isCancelled) {
      // User menekan back di kamera: kembali ke state sebelumnya.
      setState(() {
        _state = _parseResult != null
            ? ScanScreenState.confirm
            : ScanScreenState.guide;
      });
      return;
    }

    if (!result.isSuccess || result.data == null) {
      setState(() {
        _errorMessage = result.errorMessage ?? AppStrings.scanFailed;
        _state = ScanScreenState.error;
      });
      return;
    }

    final parsed = result.data!;
    setState(() {
      _parseResult = parsed;
      _queryController.text = parsed.query;
      final defaultPrice = parsed.defaultPrice;
      _selectedChipPrice = defaultPrice;
      _priceController.text = defaultPrice?.toString() ?? '';
      _state = ScanScreenState.confirm;
    });
    // Hasil OCR lengkap -> analisis langsung jalan otomatis, tanpa ketuk
    // "Cek Worth It". Layar konfirmasi hanya jadi tempat koreksi: bila OCR
    // kurang lengkap, atau bila user kembali dari layar hasil.
    if (parsed.query.trim().length >= 2 && parsed.defaultPrice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleAnalyze();
      });
    }
  }

  void _selectChipPrice(int price) {
    setState(() {
      _selectedChipPrice = price;
      _priceController.text = price.toString();
    });
  }

  void _onPriceChanged(String value) {
    // Edit manual yang menyimpang dari chip terpilih = chip tidak lagi aktif.
    if (_selectedChipPrice != null &&
        _parsePrice(value) != _selectedChipPrice) {
      setState(() => _selectedChipPrice = null);
    }
  }

  Future<void> _handleAnalyze() async {
    if (!_formKey.currentState!.validate()) return;
    final query = _queryController.text.trim();
    final price = _parsePrice(_priceController.text)!;
    setState(() => _isSubmittingAnalyze = true);
    try {
      await widget.onAnalyzeRequested(context, query, price);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _state = ScanScreenState.error;
      });
    } finally {
      if (mounted) setState(() => _isSubmittingAnalyze = false);
    }
  }

  void _handleFallbackManual() {
    final initialQuery = _queryController.text.trim();
    widget.onFallbackManual(
      context,
      initialQuery: initialQuery.isEmpty ? null : initialQuery,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.scanPriceTitle)),
      // Loading harus di tengah layar (dua sumbu), bukan ditempel spacer di
      // atas: lewati SingleChildScrollView untuk state ini, karena di dalam
      // scroll view konten selalu menempel ke atas.
      body: _state == ScanScreenState.loading
          ? Center(child: _buildLoading())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  MonexSpacing.screenPaddingH,
                  MonexSpacing.screenPaddingV,
                  MonexSpacing.screenPaddingH,
                  24,
                ),
                child: switch (_state) {
                  ScanScreenState.guide => _buildGuide(),
                  ScanScreenState.loading => _buildLoading(),
                  ScanScreenState.confirm => _buildConfirm(theme),
                  ScanScreenState.error => _buildError(theme),
                },
              ),
            ),
    );
  }

  Widget _buildGuide() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MonexSurfaceCard(
          padding: const EdgeInsets.all(MonexSpacing.cardPadding),
          radius: MonexSpacing.radiusMd,
          child: Column(
            children: [
              const Icon(
                Icons.document_scanner_outlined,
                size: 56,
                color: MonexColors.lime,
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.scanGuideTitle,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(AppStrings.scanGuideHint, textAlign: TextAlign.center),
            ],
          ),
        ),
        const SizedBox(height: MonexSpacing.sectionGap),
        MonexPrimaryButton(
          label: AppStrings.scanTakePhoto,
          icon: Icons.camera_alt_outlined,
          onPressed: () => _handlePickImage(ImageSource.camera),
        ),
        const SizedBox(height: 10),
        MonexSecondaryButton(
          label: AppStrings.scanPickFromGallery,
          icon: Icons.photo_library_outlined,
          onPressed: () => _handlePickImage(ImageSource.gallery),
        ),
      ],
    );
  }

  Widget _buildLoading() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MonexOrbitLoader(size: 56),
        SizedBox(height: 16),
        Text(AppStrings.scanReading),
      ],
    );
  }

  Widget _buildConfirm(ThemeData theme) {
    final candidates = _parseResult?.priceCandidates ?? const <int>[];
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(AppStrings.scanConfirmTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(AppStrings.scanConfirmHint),
          const SizedBox(height: MonexSpacing.sectionGap),
          TextFormField(
            controller: _queryController,
            decoration: const InputDecoration(
              labelText: AppStrings.queryLabel,
              prefixIcon: Icon(Icons.search),
            ),
            validator: (v) =>
                (v == null || v.trim().length < 2) ? AppStrings.queryMin : null,
          ),
          const SizedBox(height: MonexSpacing.sectionGap),
          TextFormField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            onChanged: _onPriceChanged,
            decoration: const InputDecoration(
              labelText: AppStrings.priceLabel,
              prefixText: 'Rp ',
            ),
            validator: (v) =>
                _parsePrice(v ?? '') == null ? AppStrings.priceInvalid : null,
          ),
          if (candidates.length > 1) ...[
            const SizedBox(height: MonexSpacing.sectionGap),
            const Text(AppStrings.scanPriceChoiceLabel),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final price in candidates)
                  ChoiceChip(
                    label: Text(formatRupiah(price)),
                    selected: _selectedChipPrice == price,
                    onSelected: (_) => _selectChipPrice(price),
                  ),
              ],
            ),
          ],
          const SizedBox(height: MonexSpacing.sectionGap + 6),
          MonexPrimaryButton(
            label: AppStrings.scanCheckButton,
            icon: Icons.analytics_outlined,
            loading: _isSubmittingAnalyze,
            onPressed: _isSubmittingAnalyze ? null : _handleAnalyze,
          ),
          const SizedBox(height: 10),
          MonexSecondaryButton(
            label: AppStrings.scanRetake,
            icon: Icons.camera_alt_outlined,
            onPressed: () => _handlePickImage(ImageSource.camera),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        Icon(
          Icons.error_outline_rounded,
          size: 56,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          _errorMessage ?? AppStrings.scanFailed,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: MonexSpacing.sectionGap),
        MonexPrimaryButton(
          label: AppStrings.scanRetry,
          icon: Icons.camera_alt_outlined,
          onPressed: () => _handlePickImage(ImageSource.camera),
        ),
        const SizedBox(height: 10),
        MonexSecondaryButton(
          label: AppStrings.scanManualButton,
          icon: Icons.edit_outlined,
          onPressed: _handleFallbackManual,
        ),
      ],
    );
  }
}
