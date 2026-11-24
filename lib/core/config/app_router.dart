import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/decks/presentation/pages/deck_cards_page.dart';
import '../../features/decks/presentation/pages/deck_list_page.dart';
import '../../features/nlp_extractor/presentation/pages/nlp_extractor_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/stats/presentation/pages/stats_page.dart';
import '../../features/study_session/presentation/pages/study_session_page.dart';
import '../ui/pixel_widgets.dart';
import 'app_theme.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/decks',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/decks',
                builder: (context, state) => const DeckListPage(),
                routes: [
                  GoRoute(
                    path: 'study/:deckId',
                    builder: (context, state) {
                      final deckId = state.pathParameters['deckId']!;
                      return StudySessionPage(deckId: deckId);
                    },
                  ),
                  GoRoute(
                    path: 'cards/:deckId',
                    builder: (context, state) {
                      final deckId = state.pathParameters['deckId']!;
                      return DeckCardsPage(deckId: deckId);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/extractor',
                builder: (context, state) => const NlpExtractorPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/stats',
                builder: (context, state) => const StatsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class MainShellScaffold extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainShellScaffold({super.key, required this.navigationShell});

  static const _tabs = [
    (icon: Icons.style_outlined, activeIcon: Icons.style, label: 'Bộ thẻ'),
    (
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
      label: 'Tách từ NLP'
    ),
    (
      icon: Icons.insights_outlined,
      activeIcon: Icons.insights,
      label: 'Thống kê'
    ),
    (icon: Icons.tune_outlined, activeIcon: Icons.tune, label: 'Cài đặt'),
  ];

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);
    final current = navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: px.canvas,
      body: WoodPlankBackground(child: navigationShell),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: px.wood,
          border: Border(
            top: BorderSide(color: px.border, width: 3),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: px.woodHighlight, width: 2),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final tab = _tabs[i];
                  final isSelected = i == current;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => navigationShell.goBranch(i),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 90),
                            transform: Matrix4.translationValues(
                              0,
                              isSelected ? -1 : 0,
                              0,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected ? px.primary : px.woodShadow,
                              border: Border.all(
                                color: isSelected
                                    ? px.primaryBorder
                                    : px.border,
                                width: 2.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: px.shadow,
                                  offset: Offset(0, isSelected ? 3 : 2),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected ? tab.activeIcon : tab.icon,
                                  size: 20,
                                  color: isSelected ? px.ink : px.inkOnWood,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  tab.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: AppTheme.pixelDisplayFont,
                                    fontFamilyFallback: AppTheme.fontFallback,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected ? px.ink : px.inkOnWood,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
