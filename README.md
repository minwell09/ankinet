# VocabAnki Graph (Flutter Android Project)

An **AnkiDroid-inspired vocabulary learning application** built with **Flutter** and **Feature-First Clean Architecture**, featuring:

1. **NLP Text Extractor (`features/nlp_extractor`)**:
   - Paste any raw text (articles, subtitles, sentences) or share text from other Android apps.
   - Auto-tokenizes words, generates phonetic transcriptions (IPA / Pinyin / Furigana), translates meanings, and decomposes words into **structural radicals / morpheme roots**.
   - Prompts the user to select desired words and batch-creates flashcards + graph edges in a single transaction.
2. **Radical & Vocabulary Knowledge Graph (`features/knowledge_graph`)**:
   - Interactive force-directed network visualization (`CustomPainter` + `InteractiveViewer`) showing relationships between saved vocabulary words and their structural radicals.
3. **Anki Decks & SM-2 Spaced Repetition (`features/decks` & `features/study_session`)**:
   - Offline-first SQLite storage (`cards`, `decks`, `radicals`, `card_radical_edges`).
   - Full SM-2 Spaced Repetition scheduler (`Again`, `Hard`, `Good`, `Easy`) calculating intervals, repetitions, and ease factors.

## Project Structure

```text
vocab_anki/
├── android/                                  # Android native host & Share Intent config
├── lib/
│   ├── main.dart                             # App entry point & ProviderScope
│   ├── core/
│   │   ├── config/
│   │   │   ├── app_router.dart               # GoRouter BottomNav shell (Decks, Extractor, Graph)
│   │   │   ├── app_theme.dart                # Material 3 Light/Dark themes
│   │   │   └── injection_container.dart      # GetIt service locator setup
│   │   ├── database/
│   │   │   └── local_database.dart           # SQLite schema (decks, cards, radicals, edges)
│   │   ├── error/
│   │   │   └── failures.dart                 # Domain Failure types
│   │   └── srs/
│   │       └── sm2_scheduler.dart            # Anki SM-2 review interval & ease calculator
│   └── features/
│       ├── nlp_extractor/                    # Text -> Tokenize/Phonetics/Radicals -> Cards
│       │   ├── data/
│       │   │   ├── datasources/nlp_analyzer_datasource.dart
│       │   │   ├── models/extracted_token_model.dart
│       │   │   └── repositories/nlp_extractor_repository_impl.dart
│       │   ├── domain/
│       │   │   ├── entities/extracted_token.dart
│       │   │   ├── repositories/nlp_extractor_repository.dart
│       │   │   └── usecases/
│       │   │       ├── analyze_text_usecase.dart
│       │   │       └── create_cards_from_tokens_usecase.dart
│       │   └── presentation/
│       │       ├── pages/nlp_extractor_page.dart
│       │       ├── providers/nlp_extractor_provider.dart
│       │       └── widgets/selectable_token_chip.dart
│       ├── knowledge_graph/                  # Force-directed Word <-> Radical Graph
│       │   ├── data/repositories/knowledge_graph_repository_impl.dart
│       │   ├── domain/
│       │   │   ├── entities/
│       │   │   │   ├── graph_edge.dart
│       │   │   │   └── graph_node.dart
│       │   │   ├── repositories/knowledge_graph_repository.dart
│       │   │   └── usecases/get_vocabulary_graph_usecase.dart
│       │   └── presentation/
│       │       ├── pages/knowledge_graph_page.dart
│       │       ├── providers/knowledge_graph_provider.dart
│       │       └── widgets/force_directed_graph_canvas.dart
│       ├── decks/                            # Anki Deck overview & card counts
│       │   ├── data/repositories/deck_repository_impl.dart
│       │   ├── domain/
│       │   │   ├── entities/
│       │   │   │   ├── deck.dart
│       │   │   │   └── vocab_card.dart
│       │   │   └── repositories/deck_repository.dart
│       │   └── presentation/
│       │       ├── pages/deck_list_page.dart
│       │       └── providers/deck_provider.dart
│       └── study_session/                    # Flashcard flip & SM-2 grading UI
│           └── presentation/pages/study_session_page.dart
└── pubspec.yaml
```
