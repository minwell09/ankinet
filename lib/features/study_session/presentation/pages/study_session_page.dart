import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/settings/study_settings.dart';
import '../../../../core/srs/fsrs_scheduler.dart';
import '../../../../core/srs/sm2_scheduler.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../../decks/presentation/providers/deck_provider.dart';
import '../../../decks/presentation/widgets/card_edit_dialog.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../stats/presentation/providers/stats_provider.dart';
import '../providers/study_session_provider.dart';
import '../widgets/tcg_flashcard_face.dart';

class StudySessionPage extends ConsumerStatefulWidget {
  final String deckId;
  final bool extraNew;

  const StudySessionPage({
    super.key,
    required this.deckId,
    this.extraNew = false,
  });

  @override
  ConsumerState<StudySessionPage> createState() => _StudySessionPageState();
}

class _StudySessionPageState extends ConsumerState<StudySessionPage> {
  @override
  void initState() {
    super.initState();
    if (widget.extraNew) {
      Future.microtask(() {
        if (!mounted) return;
        ref
            .read(studySessionProvider(widget.deckId).notifier)
            .loadExtraNewCards();
      });
    }
  }

  String _formatIntervalPreview(FsrsScheduleOutput out) {
    final mins = out.nextReviewAt.difference(DateTime.now()).inMinutes;
    if (out.intervalDays <= 0 || mins < 60 * 18) {
      if (mins < 60) return '${mins.clamp(1, 59)}m';
      return '${(mins / 60).round()}h';
    }
    if (out.intervalDays >= 365) {
      return '${(out.intervalDays / 365).toStringAsFixed(1)}y';
    }
    if (out.intervalDays >= 30) {
      return '${(out.intervalDays / 30).toStringAsFixed(1)}mo';
    }
    return '${out.intervalDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final deckId = widget.deckId;
    final px = PixelColors.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final session = ref.watch(studySessionProvider(deckId));
    final notifier = ref.read(studySessionProvider(deckId).notifier);
    final settings =
        ref.watch(studySettingsProvider).valueOrNull ?? const StudySettings();

    ref.listen<StudySessionState>(studySessionProvider(deckId), (prev, next) {
      if (next.snackbarMessage != null &&
          next.snackbarMessage != prev?.snackbarMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor:
                next.snackbarIsError ? px.coral : px.border,
            content: Text(next.snackbarMessage!),
          ),
        );
        notifier.clearSnackbar();
      }
    });

    if (session.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('ÔN TẬP FSRS-4.5')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (session.errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('ÔN TẬP FSRS-4.5')),
        body: Center(
          child: PixelCard(
            margin: const EdgeInsets.all(20),
            backgroundColor: colorScheme.errorContainer,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(session.errorMessage!),
                const SizedBox(height: 12),
                PixelButton(
                  label: 'THỬ LẠI',
                  onPressed: notifier.loadQueue,
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (session.isCompleted || session.currentCard == null) {
      final decks = ref.watch(deckListProvider).valueOrNull ?? const [];
      final matchingDeck = decks.where((d) => d.id == deckId).firstOrNull;
      final remainingNewInDeck = matchingDeck?.totalNewCards ?? 0;

      return Scaffold(
        backgroundColor: px.canvas,
        appBar: AppBar(title: const Text('HOÀN THÀNH QUEST!')),
        body: WoodPlankBackground(
          child: Center(
            child: PixelCard(
              woodFrame: true,
              showRivets: true,
              backgroundColor: px.cardParchment,
              margin: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events_rounded, size: 64, color: px.primary),
                    const SizedBox(height: 14),
                    Text(
                      'STAGE CLEAR!',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      remainingNewInDeck > 0
                          ? 'Bạn đã hoàn thành hạn mức thẻ mới hôm nay (${session.reviewedCount} lượt ôn). Bộ thẻ vẫn còn $remainingNewInDeck thẻ mới chưa học!'
                          : 'Bạn đã hoàn thành toàn bộ thẻ đến hạn hôm nay (${session.reviewedCount} lượt ôn).',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: px.inkMuted),
                    ),
                    const SizedBox(height: 18),
                    if (remainingNewInDeck > 0) ...[
                      PixelButton(
                        expand: true,
                        label: 'HỌC THÊM THẺ MỚI ($remainingNewInDeck THẺ)',
                        icon: Icons.bolt_rounded,
                        backgroundColor: px.primary,
                        foregroundColor: px.ink,
                        onPressed: notifier.loadExtraNewCards,
                      ),
                      const SizedBox(height: 10),
                    ],
                    PixelButton(
                      expand: true,
                      label: 'QUAY LẠI BỘ THẺ',
                      icon: Icons.arrow_back,
                      backgroundColor: px.emerald,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final card = session.currentCard!;
    final total = session.queue.length;
    final progress = total > 0 ? (session.currentIndex + 1) / total : 0.0;
    final activeFsrs = settings.hasCustomFsrsWeights
        ? FsrsScheduler(w: settings.effectiveFsrsWeights)
        : const FsrsScheduler();

    FsrsScheduleOutput previewFor(ReviewGrade grade) => activeFsrs.schedule(
          grade: grade,
          currentState: card.state,
          currentStepIndex: card.stepIndex,
          currentStability: card.stability,
          currentDifficulty: card.difficulty,
          currentIntervalDays: card.intervalDays,
          currentReps: card.repetitions,
          currentLapses: card.lapses,
          lastReviewAt: card.lastReviewAt,
          desiredRetention: settings.desiredRetention,
          learningStepsMinutes: settings.learningStepsMinutes,
          relearningStepsMinutes: settings.relearningStepsMinutes,
          leechThreshold: settings.leechThreshold,
          suspendLeeches: settings.suspendLeeches,
        );

    final stateLabel = switch (card.state) {
      CardState.newCard => 'NEW',
      CardState.learning => 'LEARN',
      CardState.review => 'REVIEW',
      CardState.relearning => 'RELEARN',
    };

    return Scaffold(
      backgroundColor: px.canvas,
      appBar: AppBar(
        title: Text('CARD ${session.currentIndex + 1} / $total'),
        actions: [
          IconButton(
            tooltip: 'Sửa thẻ & POS',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () async {
              final form = await showPixelEditCardDialog(context, card);
              if (form == null) return;
              final ok = await notifier.editCurrentCard(
                word: form.word,
                partOfSpeech: form.partOfSpeech,
                phoneticUs: form.phoneticUs,
                phoneticUk: form.phoneticUk,
                translation: form.translation,
                contextSentence: form.contextSentence,
              );
              if (ok) {
                ref.invalidate(deckListProvider);
                ref.invalidate(deckCardsProvider(deckId));
              }
            },
          ),
          IconButton(
            tooltip: 'Xóa thẻ này',
            icon: Icon(Icons.delete_outline_rounded, color: px.coral),
            onPressed: () async {
              final confirmed = await showPixelDeleteConfirmDialog(
                context,
                title: 'XÓA THẺ "${card.word.toUpperCase()}"?',
                message: 'Thẻ này sẽ bị xóa vĩnh viễn khỏi bộ thẻ.',
              );
              if (!confirmed) return;
              final ok = await notifier.deleteCurrentCard();
              if (ok) {
                ref.invalidate(deckListProvider);
                ref.invalidate(deckCardsProvider(deckId));
                ref.invalidate(studyStatsProvider);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: PixelBadge(
                label: stateLabel,
                backgroundColor: px.gold,
                foregroundColor: const Color(0xFF1E1B2E),
              ),
            ),
          ),
        ],
      ),
      body: WoodPlankBackground(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PixelProgressBar(
                progress: progress,
                fillColor: px.emerald,
                height: 20,
              ),
              const SizedBox(height: 16),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.08, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  );
                },
                child: LayoutBuilder(
                  key: ValueKey('${card.id}_${session.currentIndex}'),
                  builder: (context, constraints) {
                    const double tcgAspectRatio = 0.70;
                    final double maxH =
                        (constraints.maxHeight - 8).clamp(320.0, 660.0);
                    final double maxW =
                        (constraints.maxWidth - 8).clamp(240.0, 460.0);
                    final double cardW =
                        math.min(maxW, maxH * tcgAspectRatio);
                    final double cardH = cardW / tcgAspectRatio;

                    return Center(
                      child: SizedBox(
                        width: cardW,
                        height: cardH,
                        child: PixelFlipCard(
                          useCustomFrame: true,
                          isFlipped: session.showAnswer,
                          onFlipChanged: (flipped) =>
                              notifier.setFlipped(flipped, settings),
                          front: TcgFlashcardFace(
                            card: card,
                            isBack: false,
                            cardIndex: session.currentIndex,
                            totalCards: total,
                            targetAccent: settings.targetAccent,
                            showClozeContext: settings.showClozeContext,
                            relatedWords: session.relatedWords,
                            onSpeakAccent: (accent) => notifier.speakWord(
                              card.word,
                              audioUrl:
                                  accent == 'en-US' ? card.audioUrl : null,
                              accent: accent,
                            ),
                            onEnqueueRelated: notifier.enqueueRelatedCard,
                          ),
                          back: TcgFlashcardFace(
                            card: card,
                            isBack: true,
                            cardIndex: session.currentIndex,
                            totalCards: total,
                            targetAccent: settings.targetAccent,
                            showClozeContext: settings.showClozeContext,
                            relatedWords: session.relatedWords,
                            onSpeakAccent: (accent) => notifier.speakWord(
                              card.word,
                              audioUrl:
                                  accent == 'en-US' ? card.audioUrl : null,
                              accent: accent,
                            ),
                            onEnqueueRelated: notifier.enqueueRelatedCard,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (!session.hasRevealed)
              PixelButton(
                expand: true,
                label: 'LẬT THẺ (HIỆN ĐÁP ÁN)',
                icon: Icons.flip_rounded,
                backgroundColor: px.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                onPressed: () => notifier.revealAnswer(settings),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: PixelButton(
                      label: 'AGAIN',
                      sublabel: _formatIntervalPreview(
                        previewFor(ReviewGrade.again),
                      ),
                      backgroundColor: px.coral,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () async {
                        final ok = await notifier.gradeCurrentCard(
                          ReviewGrade.again,
                          settings,
                        );
                        if (ok) {
                          ref.invalidate(deckListProvider);
                          ref.invalidate(studyStatsProvider);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PixelButton(
                      label: 'HARD',
                      sublabel: _formatIntervalPreview(
                        previewFor(ReviewGrade.hard),
                      ),
                      backgroundColor: px.gold,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () async {
                        final ok = await notifier.gradeCurrentCard(
                          ReviewGrade.hard,
                          settings,
                        );
                        if (ok) {
                          ref.invalidate(deckListProvider);
                          ref.invalidate(studyStatsProvider);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PixelButton(
                      label: 'GOOD',
                      sublabel: _formatIntervalPreview(
                        previewFor(ReviewGrade.good),
                      ),
                      backgroundColor: px.emerald,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () async {
                        final ok = await notifier.gradeCurrentCard(
                          ReviewGrade.good,
                          settings,
                        );
                        if (ok) {
                          ref.invalidate(deckListProvider);
                          ref.invalidate(studyStatsProvider);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PixelButton(
                      label: 'EASY',
                      sublabel: _formatIntervalPreview(
                        previewFor(ReviewGrade.easy),
                      ),
                      backgroundColor: px.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      onPressed: () async {
                        final ok = await notifier.gradeCurrentCard(
                          ReviewGrade.easy,
                          settings,
                        );
                        if (ok) {
                          ref.invalidate(deckListProvider);
                          ref.invalidate(studyStatsProvider);
                        }
                      },
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      ),
    );
  }
}
