import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/api_result.dart';
import 'package:worthbang/utils/rupiah.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/models/trend_models.dart';
import 'package:worthbang/services/trends_api.dart';

/// Tab Tren: grafik harga 30 hari + min/max/avg/perubahan + ringkasan deskriptif.
class TrendsScreenContent extends ConsumerStatefulWidget {
  const TrendsScreenContent({super.key, this.initialQuery = 'RTX 4060'});

  final String initialQuery;

  @override
  ConsumerState<TrendsScreenContent> createState() =>
      _TrendsScreenContentState();
}

class _TrendsScreenContentState
    extends ConsumerState<TrendsScreenContent> {
  final _query = TextEditingController();
  int _days = 30;
  ApiResult<TrendData>? _state;

  @override
  void initState() {
    super.initState();
    _query.text = widget.initialQuery;
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_query.text.trim().isEmpty) return;
    setState(() => _state = const ApiLoading());
    try {
      final data = await ref
          .read(trendsApiProvider)
          .getTrend(_query.text.trim(), days: _days);
      setState(() => _state = ApiSuccess(data));
    } catch (e) {
      setState(() => _state = ApiError(e.toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final data =
        state is ApiSuccess<TrendData> ? state.data : null;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.trendTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            MonexSpacing.screenPaddingH,
            MonexSpacing.screenPaddingV,
            MonexSpacing.screenPaddingH,
            24,
          ),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _query,
                    decoration: const InputDecoration(
                      labelText: AppStrings.queryLabel,
                      prefixIcon: Icon(Icons.show_chart),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _days,
                  underline: const SizedBox.shrink(),
                  style: Theme.of(context).textTheme.titleSmall,
                  items: const [7, 30, 90]
                      .map((d) => DropdownMenuItem(
                          value: d, child: Text('$d hari')))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _days = v);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                MonexPrimaryButton(
                  onPressed: state is ApiLoading ? null : _load,
                  label: AppStrings.searchButton,
                  expanded: false,
                  loading: state is ApiLoading,
                ),
              ],
            ),
            const SizedBox(height: MonexSpacing.sectionGap),
            if (state is ApiLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: MonexOrbitLoader(size: 56)),
              ),
            if (state is ApiError)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  (state as ApiError<TrendData>).message,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (data != null) ...[
              _StatsRow(data: data),
              const SizedBox(height: MonexSpacing.gridGap),
              if (data.points.isNotEmpty) ...[
                SizedBox(height: 240, child: _TrendChart(data: data)),
                const SizedBox(height: MonexSpacing.gridGap),
              ],
              MonexSurfaceCard(
                padding:
                    const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
                radius: MonexSpacing.radiusMd,
                child: Text(
                  data.summary.isNotEmpty
                      ? data.summary
                      : data.localSummary(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.data});
  final TrendData data;

  @override
  Widget build(BuildContext context) {
    final change = data.changePercent;
    final Color? changeColor = change < 0
        ? MonexColors.verdictGood
        : change > 0
            ? MonexColors.danger
            : null;
    return Row(
      children: [
        _stat(context, 'Terendah', formatRupiah(data.min)),
        _stat(context, 'Tertinggi', formatRupiah(data.max)),
        _stat(context, 'Rata-rata', formatRupiah(data.avg.round())),
        _stat(
          context,
          'Perubahan',
          '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
          valueColor: changeColor,
        ),
      ],
    );
  }

  Widget _stat(BuildContext context, String label, String value,
      {Color? valueColor}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: MonexSpacing.gridGap),
        child: MonexSurfaceCard(
          radius: MonexSpacing.radiusMd,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.data});
  final TrendData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final axisColor = theme.textTheme.bodySmall?.color ?? MonexColors.textMuted;
    final spots = data.points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.price / 1e6))
        .toList();
    final minY = (data.min / 1e6 * 0.98).floorToDouble();
    final maxY = (data.max / 1e6 * 1.02).ceilToDouble();
    final dateFmt = DateFormat('d/M');

    return MonexSurfaceCard(
      radius: MonexSpacing.radiusMd,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: LineChart(
        LineChartData(
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: MonexColors.chartTrack,
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (v, _) => Text(
                  '${v.toStringAsFixed(1)}jt',
                  style: TextStyle(fontSize: 10, color: axisColor),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: (spots.length / 4).ceilToDouble(),
                getTitlesWidget: (v, _) {
                  final i = v.toInt();
                  if (i < 0 || i >= data.points.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    dateFmt.format(data.points[i].date),
                    style: TextStyle(fontSize: 10, color: axisColor),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              barWidth: 2.5,
              color: MonexColors.lime,
              belowBarData: BarAreaData(
                show: true,
                color: MonexColors.limeMuted,
              ),
              dotData: const FlDotData(show: false),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touched) => touched
                  .map((s) => LineTooltipItem(
                        '${dateFmt.format(data.points[s.x.toInt()].date)}\n'
                        '${formatRupiah((s.y * 1e6).round())}',
                        const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: MonexColors.textDark,
                        ),
                      ))
                  .toList(),
              getTooltipColor: (_) => MonexColors.surfaceElevated,
            ),
          ),
        ),
      ),
    );
  }
}
