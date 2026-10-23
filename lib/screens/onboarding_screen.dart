import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/services/features/personalization/personalization_engine.dart';

/// Onboarding personalisasi: 3 pertanyaan (kebutuhan, budget, platform)
/// sebagai modal awal profil rekomendasi. Mode edit bila onboarding
/// sudah pernah diisi — nilai lama dimuat, judul berubah.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _BudgetRange {
  const _BudgetRange(this.label, this.min, this.max);

  final String label;
  final int min;
  final int max;
}

const _budgetRanges = <_BudgetRange>[
  _BudgetRange('< 5 juta', 0, 5000000),
  _BudgetRange('5–10 juta', 5000000, 10000000),
  _BudgetRange('10–20 juta', 10000000, 20000000),
  _BudgetRange('> 20 juta', 20000000, 40000000),
];

/// Nilai yang disimpan = kode engine ('gaming', 'amd', ...);
/// label hanya untuk tampilan.
const _needLabels = <String, String>{
  'gaming': 'Gaming',
  'editing': 'Editing & konten',
  'kerja': 'Kerja & kuliah',
};
const _platformLabels = <String, String>{
  'amd': 'AMD',
  'intel': 'Intel',
  'bebas': 'Bebas',
};

class _OnboardingScreenState extends State<OnboardingScreen> {
  String? _need;
  int _budgetIdx = 1;
  String _platform = 'bebas';
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final engine =
        PersonalizationEngine(await SharedPreferences.getInstance());
    final existing = await engine.onboarding();
    if (existing == null || !mounted) return;
    var idx = _budgetRanges.indexWhere((r) => r.min == existing.budgetMin);
    if (idx < 0) {
      idx = 0;
      for (var i = 0; i < _budgetRanges.length; i++) {
        if (existing.budgetMin >= _budgetRanges[i].min) idx = i;
      }
    }
    setState(() {
      _editing = true;
      _need = existing.need;
      _budgetIdx = idx;
      _platform = existing.platform;
    });
  }

  Future<void> _save() async {
    final need = _need;
    if (need == null || _saving) return;
    setState(() => _saving = true);
    final range = _budgetRanges[_budgetIdx];
    final engine =
        PersonalizationEngine(await SharedPreferences.getInstance());
    await engine.saveOnboarding(OnboardingProfile(
      need: need,
      budgetMin: range.min,
      budgetMax: range.max,
      platform: _platform,
    ));
    if (!mounted) return;
    showMonexToast(context, AppStrings.prefSaved, isSuccess: true);
    Navigator.of(context).pop();
  }

  Widget _optionGroup<T>(
    BuildContext context, {
    required String label,
    required List<T> values,
    required String Function(T) text,
    required T? selected,
    required ValueChanged<T> onSelect,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(text(v)),
                selected: selected == v,
                onSelected: (on) {
                  if (on) onSelect(v);
                },
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _editing ? AppStrings.prefTitle : AppStrings.onboardingTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            MonexSpacing.screenPaddingH,
            MonexSpacing.screenPaddingV,
            MonexSpacing.screenPaddingH,
            24,
          ),
          children: [
            _optionGroup<String>(
              context,
              label: AppStrings.prefNeedLabel,
              values: _needLabels.keys.toList(),
              text: (v) => _needLabels[v]!,
              selected: _need,
              onSelect: (v) => setState(() => _need = v),
            ),
            const SizedBox(height: MonexSpacing.sectionGap),
            _optionGroup<int>(
              context,
              label: AppStrings.prefBudgetLabel,
              values: [for (var i = 0; i < _budgetRanges.length; i++) i],
              text: (i) => _budgetRanges[i].label,
              selected: _budgetIdx,
              onSelect: (v) => setState(() => _budgetIdx = v),
            ),
            const SizedBox(height: MonexSpacing.sectionGap),
            _optionGroup<String>(
              context,
              label: AppStrings.prefPlatformLabel,
              values: _platformLabels.keys.toList(),
              text: (v) => _platformLabels[v]!,
              selected: _platform,
              onSelect: (v) => setState(() => _platform = v),
            ),
            const SizedBox(height: MonexSpacing.sectionGap + 6),
            MonexPrimaryButton(
              label: AppStrings.saveButton,
              loading: _saving,
              onPressed: _need == null || _saving ? null : _save,
            ),
            if (!_editing) ...[
              const SizedBox(height: 8),
              MonexSecondaryButton(
                label: AppStrings.prefSkipButton,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
