import 'package:equatable/equatable.dart';

class Deck extends Equatable {
  final String id;
  final String name;
  final String description;
  final int totalCards;
  final int dueCards;
  final int newCards;
  final int learningCards;
  final int reviewDueCards;
  final int leechCards;

  const Deck({
    required this.id,
    required this.name,
    required this.description,
    required this.totalCards,
    required this.dueCards,
    this.newCards = 0,
    this.learningCards = 0,
    this.reviewDueCards = 0,
    this.leechCards = 0,
  });

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        totalCards,
        dueCards,
        newCards,
        learningCards,
        reviewDueCards,
        leechCards,
      ];
}
