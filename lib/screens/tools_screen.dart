import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/currency_api.dart';

/// Layar Konverter: mata uang (kurs server) + zona waktu WIB/WITA/WIT/UTC.
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  final _amount = TextEditingController(text: '4500000');
  String _target = 'USD';
  CurrencyRates? _rates;
  bool _loadingRates = true;
  String? _ratesError;

  WibZone _from = WibZone.wib;
  WibZone _to = WibZone.wita;
  DateTime _picked = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadRates();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _loadRates() async {
    try {
      final rates = await ref.read(currencyApiProvider).getRates();
      if (mounted) {
        setState(() {
          _rates = rates;
          _loadingRates = false;
          if (!rates.rates.containsKey(_target)) {
            _target = rates.rates.keys.first;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ratesError = e.toString();
          _loadingRates = false;
        });
      }
    }
  }

  Future<void> _pickTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _picked,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_picked),
    );
    if (time == null) return;
    setState(() {
      _picked = DateTime(
          date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  @override
  Widget build(BuildContext context) {
    final amount =
        double.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final rate = _rates?.rates[_target];
    final converted = rate != null ? convertCurrency(amount, rate) : null;
    final convertedTime = convertTimezone(_picked, _from, _to);
    final fmt = DateFormat('d MMM yyyy HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.toolsTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            MonexSpacing.screenPaddingH,
            MonexSpacing.screenPaddingV,
            MonexSpacing.screenPaddingH,
            24,
          ),
          children: [
            Text(AppStrings.currencySection,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_loadingRates)
              const Center(child: MonexOrbitLoader(size: 56))
            else if (_ratesError != null)
              Text(_ratesError!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error))
            else ...[
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: AppStrings.amountLabel,
                        prefixText: 'Rp ',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _target,
                      decoration: const InputDecoration(
                          labelText: AppStrings.toLabel),
                      items: _rates!.rates.keys
                          .map((c) => DropdownMenuItem(
                              value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _target = v ?? _target),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MonexSurfaceCard(
                padding:
                    const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
                radius: MonexSpacing.radiusMd,
                child: Text(
                    converted != null
                        ? 'Rp ${amount.toStringAsFixed(0)} = '
                            '${converted.toStringAsFixed(2)} $_target'
                        : '-',
                    style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (_rates!.updatedAt != null)
                Text(
                  'Kurs diperbarui: ${DateFormat('d MMM HH:mm').format(_rates!.updatedAt!.toLocal())}',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
            const SizedBox(height: 24),
            Text(AppStrings.timezoneSection,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: MonexSecondaryButton(
                    onPressed: _pickTime,
                    icon: Icons.schedule_rounded,
                    label: fmt.format(_picked),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<WibZone>(
                    initialValue: _from,
                    decoration: const InputDecoration(
                        labelText: AppStrings.fromLabel),
                    items: WibZone.values
                        .map((z) => DropdownMenuItem(
                            value: z, child: Text(z.label)))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _from = v ?? _from),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward),
                ),
                Expanded(
                  child: DropdownButtonFormField<WibZone>(
                    initialValue: _to,
                    decoration: const InputDecoration(
                        labelText: AppStrings.toLabel),
                    items: WibZone.values
                        .map((z) => DropdownMenuItem(
                            value: z, child: Text(z.label)))
                        .toList(),
                    onChanged: (v) => setState(() => _to = v ?? _to),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            MonexSurfaceCard(
              padding:
                  const EdgeInsets.all(MonexSpacing.cardPaddingCompact),
              radius: MonexSpacing.radiusMd,
              child: Text(
                  '${fmt.format(_picked)} ${_from.label} = '
                  '${fmt.format(convertedTime)} ${_to.label}',
                  style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
