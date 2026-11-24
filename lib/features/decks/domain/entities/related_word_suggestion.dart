import 'package:equatable/equatable.dart';

import 'vocab_card.dart';

class RelatedWordSuggestion extends Equatable {
  final VocabCard card;
  final List<String> sharedRadicals;

  const RelatedWordSuggestion({
    required this.card,
    required this.sharedRadicals,
  });

  @override
  List<Object?> get props => [card, sharedRadicals];
}
