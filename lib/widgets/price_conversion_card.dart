import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/features/currency_api.dart';
import 'package:worthbang/utils/rupiah.dart';

/// Kartu konversi harga terkonsep: harga IDR + padanan USD/SGD/MYR
/// (kurs live via [CurrencyApi], fallback offline) + jam pengecekan
/// harga di 4 zona (WIB, WITA, WIT, London).
class PriceConversionCard extends ConsumerStatefulWidget {
  const PriceConversionCard({super.key, required this.priceIdr, this.at});

  final int priceIdr;

  /// Instan pengecekan harga; default saat widget dibuat.
  final DateTime? at;

  @override
  ConsumerState<PriceConversionCard> createState() =>
      _PriceConversionCardState();
}

class _PriceConversionCardState extends ConsumerState<PriceConversionCard> {
  late final Future<CurrencyRates> _ratesFuture;

  static const _symbols = {'USD': '\$', 'SGD': 'S\$', 'MYR': 'RM'};
  static const _zones = [
    WibZone.wib,
    WibZone.wita,
    WibZone.wit,
    WibZone.london,
  ];

  @override
  void initState() {
    super.initState();
    _ratesFuture = ref.read(currencyApiProvider).getRates();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final utc = (widget.at ?? DateTime.now()).toUtc();
    final timeFmt = DateFormat('HH:mm');
    return MonexSurfaceCard(
      padding: const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
      radius: MonexSpacing.radiusMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatRupiah(widget.priceIdr),
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          FutureBuilder<CurrencyRates>(
            future: _ratesFuture,
            builder: (context, snap) {
              final rates = snap.data?.rates ?? CurrencyApi.fallbackRates;
              return Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  for (final code in _symbols.keys)
                    if (rates[code] != null)
                      Text(
                        '${_symbols[code]}${convertCurrency(widget.priceIdr.toDouble(), rates[code]!).toStringAsFixed(2)} $code',
                        style: theme.textTheme.bodyMedium,
                      ),
                ],
              );
            },
          ),
          const Divider(height: 20),
          Text(
            'Waktu Pengecekan Harga',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final z in _zones)
                Text(
                  '${z.label} ${timeFmt.format(zonedTime(utc, z))}',
                  style: theme.textTheme.bodyMedium,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
