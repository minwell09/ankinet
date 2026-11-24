import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/injection_container.dart';
import '../../../study_session/domain/usecases/study_session_usecases.dart';
import '../../domain/entities/deck.dart';
import '../../domain/entities/vocab_card.dart';
import '../../domain/usecases/get_decks_usecase.dart';
import '../../domain/usecases/manage_cards_and_decks_usecase.dart';
import '../../domain/usecases/manage_leech_cards_usecase.dart';

/// Reactive revision counter incremented whenever cards or decks are inserted,
/// edited, deleted, or imported so all tabs (including IndexedStack study queues)
/// immediately stay in sync with SQLite.
final cardsRevisionProvider = StateProvider<int>((ref) => 0);

final deckListProvider = FutureProvider.autoDispose<List<Deck>>((ref) async {
  ref.watch(cardsRevisionProvider);
  final result = await sl<GetDecksUseCase>()();
  return result.fold(
    (failure) => throw Exception(failure.message),
    (decks) => decks,
  );
});

final dueCardsProvider = FutureProvider.autoDispose
    .family<List<VocabCard>, String>((ref, deckId) async {
  ref.watch(cardsRevisionProvider);
  final result = await sl<GetDueCardsUseCase>()(deckId);
  return result.fold(
    (failure) => throw Exception(failure.message),
    (cards) => cards,
  );
});

final leechCardsProvider =
    FutureProvider.autoDispose<List<VocabCard>>((ref) async {
  ref.watch(cardsRevisionProvider);
  final result = await sl<GetLeechCardsUseCase>()();
  return result.fold(
    (failure) => throw Exception(failure.message),
    (cards) => cards,
  );
});

final deckCardsProvider = FutureProvider.autoDispose
    .family<List<VocabCard>, String>((ref, deckId) async {
  ref.watch(cardsRevisionProvider);
  final result = await sl<GetCardsByDeckUseCase>()(deckId);
  return result.fold(
    (failure) => throw Exception(failure.message),
    (cards) => cards,
  );
});
