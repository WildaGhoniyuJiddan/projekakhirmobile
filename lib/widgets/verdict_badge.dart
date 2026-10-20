import 'package:flutter/material.dart';

import 'package:worthbang/utils/theme.dart';
import 'package:worthbang/l10n/strings.dart';

/// Tingkat verdict harga dari backend (`sangat_murah`/`worth_it`/`wajar`/`kemahalan`
/// dinormalisasi ke tiga level UI).
enum Verdict { good, fair, bad }

/// Badge verdict: warna + label teks SELALU tampil bersamaan.
///
/// Jangan pernah memakai warna saja sebagai satu-satunya penanda —
/// label teks wajib ada untuk aksesibilitas.
class VerdictBadge extends StatelessWidget {
  const VerdictBadge({super.key, required this.verdict});

  final Verdict verdict;

  Color get _color => switch (verdict) {
        Verdict.good => AppTheme.verdictGood,
        Verdict.fair => AppTheme.verdictFair,
        Verdict.bad => AppTheme.verdictBad,
      };

  String get _label => switch (verdict) {
        Verdict.good => AppStrings.verdictWorthIt,
        Verdict.fair => AppStrings.verdictFair,
        Verdict.bad => AppStrings.verdictOverpriced,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          // Label teks: wajib, bukan opsional.
          Text(
            _label,
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
