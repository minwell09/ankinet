import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/decks/presentation/pages/deck_cards_page.dart';
import '../../features/decks/presentation/pages/deck_list_page.dart';
import '../../features/decks/presentation/providers/deck_provider.dart';
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
                      final extraNew =
                          state.uri.queryParameters['extraNew'] == '1';
                      return StudySessionPage(
                        deckId: deckId,
                        extraNew: extraNew,
                      );
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

class MainShellScaffold extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const MainShellScaffold({super.key, required this.navigationShell});

  static const _tabs = [
    (icon: Icons.style_outlined, activeIcon: Icons.style, label: 'Bộ thẻ'),
    (
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
      label: 'Tách từ'
    ),
    (
      icon: Icons.insights_outlined,
      activeIcon: Icons.insights,
      label: 'Thống kê'
    ),
    (icon: Icons.tune_outlined, activeIcon: Icons.tune, label: 'Cài đặt'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final px = PixelColors.of(context);
    final current = navigationShell.currentIndex;

    return Scaffold(
      backgroundColor: px.canvas,
      body: WoodPlankBackground(child: navigationShell),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF4A301E),
          border: Border(
            top: BorderSide(color: px.shadow, width: 2),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final tab = _tabs[i];
                final isSelected = i == current;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        navigationShell.goBranch(i);
                        if (i == 0) {
                          ref.read(cardsRevisionProvider.notifier).state++;
                        }
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 110),
                          transform: Matrix4.translationValues(
                            0,
                            isSelected ? -2 : 0,
                            0,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 7,
                            horizontal: 4,
                          ),
                          decoration: isSelected
                              ? BoxDecoration(
                                  color: const Color(0xFF5E3D26),
                                  border: Border.all(
                                    color: px.primary,
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: px.shadow,
                                      offset: const Offset(0, 2),
                                      blurRadius: 0,
                                    ),
                                  ],
                                )
                              : const BoxDecoration(
                                  color: Colors.transparent,
                                ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected ? tab.activeIcon : tab.icon,
                                size: 20,
                                color: isSelected
                                    ? px.primary
                                    : px.inkOnWood.withValues(alpha: 0.78),
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
                                  color: isSelected
                                      ? px.primary
                                      : px.inkOnWood.withValues(alpha: 0.78),
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
    );
  }
}
