import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/screens/login_screen.dart';
import '../../features/lobby/screens/lobby_screen.dart';
import '../../features/game/screens/game_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/achievements/screens/achievements_screen.dart';
import '../../features/matchmaking/screens/matchmaking_screen.dart';
import '../providers/auth_provider.dart';

part 'app_router.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Route constants
// ─────────────────────────────────────────────────────────────────────────────
abstract class Routes {
  static const login = '/auth/login';
  static const lobby = '/lobby';
  static const profile = '/profile';
  static const achievements = '/achievements';
  static const matchmaking = '/matchmaking';
  static const game = '/game/:sessionId';

  static String gameWithId(String sessionId) => '/game/$sessionId';
}

// ─────────────────────────────────────────────────────────────────────────────
// Router provider
// ─────────────────────────────────────────────────────────────────────────────
@riverpod
GoRouter appRouter(AppRouterRef ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: Routes.lobby,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isLoggedIn = authState.valueOrNull != null;
      final isOnAuthRoute = state.fullPath?.startsWith('/auth') ?? false;

      if (!isLoggedIn && !isOnAuthRoute) return Routes.login;
      if (isLoggedIn && isOnAuthRoute) return Routes.lobby;
      return null;
    },
    routes: [
      // ── Auth ────────────────────────────────────────────────────
      GoRoute(
        path: Routes.login,
        name: 'login',
        pageBuilder: (ctx, state) => _buildPage(
          state,
          const LoginScreen(),
          transitionType: _PageTransition.fade,
        ),
      ),

      // ── Main Shell (shared nav) ──────────────────────────────────
      ShellRoute(
        builder: (ctx, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path: Routes.lobby,
            name: 'lobby',
            pageBuilder: (ctx, state) =>
                _buildPage(state, const LobbyScreen()),
          ),
          GoRoute(
            path: Routes.profile,
            name: 'profile',
            pageBuilder: (ctx, state) =>
                _buildPage(state, const ProfileScreen()),
          ),
          GoRoute(
            path: Routes.achievements,
            name: 'achievements',
            pageBuilder: (ctx, state) =>
                _buildPage(state, const AchievementsScreen()),
          ),
          GoRoute(
            path: Routes.matchmaking,
            name: 'matchmaking',
            pageBuilder: (ctx, state) =>
                _buildPage(state, const MatchmakingScreen()),
          ),
        ],
      ),

      // ── Game (fullscreen, no shell) ──────────────────────────────
      GoRoute(
        path: Routes.game,
        name: 'game',
        pageBuilder: (ctx, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return _buildPage(
            state,
            GameScreen(sessionId: sessionId),
            transitionType: _PageTransition.scale,
          );
        },
      ),
    ],

    errorBuilder: (ctx, state) => Scaffold(
      body: Center(
        child: Text('Route not found: ${state.error}'),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Page transition helper
// ─────────────────────────────────────────────────────────────────────────────
enum _PageTransition { slide, fade, scale }

CustomTransitionPage<void> _buildPage(
  GoRouterState state,
  Widget child, {
  _PageTransition transitionType = _PageTransition.slide,
}) {
  return CustomTransitionPage(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );

      switch (transitionType) {
        case _PageTransition.fade:
          return FadeTransition(opacity: curved, child: child);
        case _PageTransition.scale:
          return ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
        case _PageTransition.slide:
          return SlideTransition(
            position: Tween(
              begin: const Offset(1.0, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
      }
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// App Shell (wraps nav screens)
// ─────────────────────────────────────────────────────────────────────────────
class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context) => child;
}
