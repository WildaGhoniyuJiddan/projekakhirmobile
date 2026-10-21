import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:worthbang/core/theme/monex_theme.dart';
import 'package:worthbang/core/widgets/monex_widgets.dart';
import 'package:worthbang/services/core/api_result.dart';
import 'package:worthbang/utils/rupiah.dart';
import 'package:worthbang/l10n/strings.dart';
import 'package:worthbang/services/features/game_api.dart';
import 'package:worthbang/models/game_models.dart';
import 'package:worthbang/screens/zero_g_thermal_screen.dart';

/// Game Tebak Harga: 5 ronde, tebak harga produk, skor per ronde 0–100.
/// Total disimpan sebagai high score lokal.
class GameScreen extends ConsumerStatefulWidget {
  const GameScreen({super.key});

  static const rounds = 5;

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  final _guess = TextEditingController();

  int _round = 1;
  int _totalScore = 0;
  ApiResult<GameQuestion>? _questionState;
  GuessResult? _lastResult;
  bool _submitting = false;
  bool _finished = false;
  bool _newRecord = false;
  int _best = 0;

  @override
  void initState() {
    super.initState();
    _loadBest();
    _loadQuestion();
  }

  @override
  void dispose() {
    _guess.dispose();
    super.dispose();
  }

  Future<void> _loadBest() async {
    final store = await ref.read(highScoreStoreProvider.future);
    if (mounted) setState(() => _best = store.bestScore);
  }

  Future<void> _loadQuestion() async {
    setState(() {
      _questionState = const ApiLoading();
      _lastResult = null;
      _guess.clear();
    });
    try {
      final q = await ref.read(gameApiProvider).getQuestion();
      if (mounted) setState(() => _questionState = ApiSuccess(q));
    } catch (e) {
      if (mounted) setState(() => _questionState = ApiError(e.toString()));
    }
  }

  Future<void> _submit() async {
    final state = _questionState;
    if (state is! ApiSuccess<GameQuestion> || _submitting) return;
    final guess =
        int.tryParse(_guess.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (guess <= 0) return;
    FocusScope.of(context).unfocus();
    setState(() => _submitting = true);
    try {
      final result = await ref.read(gameApiProvider).submitGuess(
            questionId: state.data.questionId,
            guessIdr: guess,
          );
      if (!mounted) return;
      setState(() {
        _lastResult = result;
        _totalScore += result.score;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showMonexToast(context, e.toString(), isError: true);
    }
  }

  Future<void> _next() async {
    if (_round >= GameScreen.rounds) {
      final store = await ref.read(highScoreStoreProvider.future);
      final isRecord = await store.saveScore(_totalScore);
      if (mounted) {
        setState(() {
          _finished = true;
          _newRecord = isRecord;
          _best = store.bestScore;
        });
      }
      return;
    }
    setState(() => _round++);
    await _loadQuestion();
  }

  void _restart() {
    setState(() {
      _round = 1;
      _totalScore = 0;
      _finished = false;
      _newRecord = false;
    });
    _loadQuestion();
  }

  @override
  Widget build(BuildContext context) {
    final state = _questionState;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.gameTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.developer_board_rounded, color: MonexColors.lime),
            tooltip: 'Protokol Termal Zero-G',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ZeroGThermalScreen()),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'Skor: $_totalScore',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: MonexColors.lime,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: _finished
            ? _buildFinished()
            : Padding(
                padding: const EdgeInsets.fromLTRB(
                  MonexSpacing.screenPaddingH,
                  MonexSpacing.screenPaddingV,
                  MonexSpacing.screenPaddingH,
                  24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ronde $_round/${GameScreen.rounds}',
                            style: theme.textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Rekor: $_best',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    MonexProgressBar(value: _round / GameScreen.rounds),
                    const SizedBox(height: MonexSpacing.sectionGap),
                    if (state is ApiLoading)
                      const Expanded(
                        child: Center(child: MonexOrbitLoader(size: 56)),
                      ),
                    if (state is ApiError)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text((state as ApiError<GameQuestion>).message,
                                  textAlign: TextAlign.center),
                              const SizedBox(height: 12),
                              MonexPrimaryButton(
                                onPressed: _loadQuestion,
                                label: AppStrings.retryButton,
                                expanded: false,
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (state is ApiSuccess<GameQuestion>)
                      Expanded(child: _buildRound(state.data)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildRound(GameQuestion q) {
    final result = _lastResult;
    final theme = Theme.of(context);
    return ListView(
      children: [
        MonexSurfaceCard(
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: MonexColors.limeMuted,
                  borderRadius:
                      BorderRadius.circular(MonexSpacing.radiusCard),
                ),
                child: const Icon(Icons.help_outline,
                    size: 30, color: MonexColors.lime),
              ),
              const SizedBox(height: MonexSpacing.gridGap),
              Text(
                q.product,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(q.specs, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                '💡 ${q.hint}',
                style: const TextStyle(fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: MonexSpacing.sectionGap),
        if (result == null) ...[
          TextField(
            controller: _guess,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: AppStrings.guessLabel,
              prefixText: 'Rp ',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: MonexSpacing.gridGap),
          MonexPrimaryButton(
            onPressed: _submitting ? null : _submit,
            label: AppStrings.submitGuessButton,
            loading: _submitting,
          ),
        ] else ...[
          MonexSurfaceCard(
            color: result.score >= 80
                ? MonexColors.verdictGood.withValues(alpha: 0.12)
                : result.score >= 50
                    ? MonexColors.verdictFair.withValues(alpha: 0.12)
                    : MonexColors.danger.withValues(alpha: 0.12),
            borderColor: result.score >= 80
                ? MonexColors.verdictGood.withValues(alpha: 0.4)
                : result.score >= 50
                    ? MonexColors.verdictFair.withValues(alpha: 0.4)
                    : MonexColors.danger.withValues(alpha: 0.4),
            child: Column(
              children: [
                Text('+${result.score}',
                    style: theme.textTheme.displaySmall),
                const SizedBox(height: 4),
                Text('Harga asli: ${formatRupiah(result.actualPrice)}'),
                Text(
                  result.difference == 0
                      ? 'Tepat sekali! 🎯'
                      : result.difference > 0
                          ? 'Tebakanmu ${formatRupiah(result.difference)} lebih mahal'
                          : 'Tebakanmu ${formatRupiah(-result.difference)} lebih murah',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: MonexSpacing.gridGap),
          MonexPrimaryButton(
            onPressed: _next,
            label: _round >= GameScreen.rounds
                ? AppStrings.finishButton
                : AppStrings.nextRoundButton,
          ),
        ],
      ],
    );
  }

  Widget _buildFinished() {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(MonexSpacing.screenPaddingH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: MonexColors.limeMuted,
                borderRadius:
                    BorderRadius.circular(MonexSpacing.radiusCard),
              ),
              child: const Icon(Icons.emoji_events,
                  size: 40, color: MonexColors.lime),
            ),
            const SizedBox(height: MonexSpacing.sectionGap),
            Text(
              AppStrings.gameFinished,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Skor total: $_totalScore / ${GameScreen.rounds * 100}',
              style: theme.textTheme.titleLarge,
            ),
            if (_newRecord)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  AppStrings.newRecord,
                  style: TextStyle(
                    color: MonexColors.verdictGood,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Rekor: $_best'),
              ),
            const SizedBox(height: 24),
            MonexPrimaryButton(
              onPressed: _restart,
              icon: Icons.replay_rounded,
              label: AppStrings.playAgainButton,
              expanded: false,
            ),
          ],
        ),
      ),
    );
  }
}
