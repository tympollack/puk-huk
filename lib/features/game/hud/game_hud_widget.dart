import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/puk_huk_theme.dart';
import '../../../data/models/game_session_model.dart';
import '../providers/game_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GameHudWidget
// Floating overlay rendered above the Flame game canvas.
// Receives live session state from RTDB via gameSessionProvider.
// ─────────────────────────────────────────────────────────────────────────────
class GameHudWidget extends ConsumerWidget {
  final String sessionId;
  final String localPlayerId;

  const GameHudWidget({
    super.key,
    required this.sessionId,
    required this.localPlayerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(gameSessionProvider(sessionId));

    return sessionAsync.when(
      data: (session) => _HudOverlay(
        session: session,
        localPlayerId: localPlayerId,
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main overlay — positions all HUD panels
// ─────────────────────────────────────────────────────────────────────────────
class _HudOverlay extends StatelessWidget {
  final GameSessionState session;
  final String localPlayerId;

  const _HudOverlay({required this.session, required this.localPlayerId});

  String get _oppId => session.scores.keys.firstWhere(
        (id) => id != localPlayerId,
        orElse: () => '',
      );

  @override
  Widget build(BuildContext context) {
    final myScore = session.scores[localPlayerId] ?? 0;
    final oppScore = session.scores[_oppId] ?? 0;
    final isMyTurn = session.currentTurnPlayerId == localPlayerId;

    return Stack(
      children: [
        // ── Top-center: Score + Round Banner ────────────────────────
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: _ScoreBanner(
            myScore: myScore,
            oppScore: oppScore,
            round: session.turnNumber,
            totalRounds: 10,
          ),
        ),

        // ── Turn indicator pulse ─────────────────────────────────────
        if (isMyTurn)
          Positioned(
            bottom: 58,
            left: 0,
            right: 0,
            child: const _TurnIndicator(),
          ),

        // ── Round transition splash ──────────────────────────────────
        if (session.status == 'waiting')
          const _WaitingOverlay(),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score Banner — top-center pill showing scores + round counter
// ─────────────────────────────────────────────────────────────────────────────
class _ScoreBanner extends StatelessWidget {
  final int myScore, oppScore, round, totalRounds;

  const _ScoreBanner({
    required this.myScore,
    required this.oppScore,
    required this.round,
    required this.totalRounds,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
        decoration: BoxDecoration(
          color: PukHukTheme.hudBackground,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: PukHukTheme.hudBorder),
          boxShadow: [
            BoxShadow(
              color: PukHukTheme.primary.withOpacity(0.12),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // My score
            _AnimatedScore(score: myScore, color: PukHukTheme.primary),

            // Divider + Round info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'TURN',
                    style: GoogleFonts.orbitron(
                      fontSize: 8,
                      color: PukHukTheme.textSecondary,
                      letterSpacing: 2.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$round',
                    style: GoogleFonts.orbitron(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: PukHukTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            // Opponent score
            _AnimatedScore(score: oppScore, color: PukHukTheme.secondary),
          ],
        ),
      ),
    );
  }
}

class _AnimatedScore extends StatelessWidget {
  final int score;
  final Color color;

  const _AnimatedScore({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      score.toString().padLeft(2, '0'),
      style: GoogleFonts.orbitron(
        fontSize: 38,
        fontWeight: FontWeight.w700,
        color: color,
        shadows: [Shadow(color: color.withOpacity(0.45), blurRadius: 14)],
      ),
    )
        .animate(key: ValueKey(score))
        .scale(
          begin: const Offset(1.35, 1.35),
          end: const Offset(1, 1),
          duration: 350.ms,
          curve: Curves.elasticOut,
        )
        .fade(begin: 0.5, end: 1.0, duration: 200.ms);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Turn Indicator — animated pulse at bottom-center
// ─────────────────────────────────────────────────────────────────────────────
class _TurnIndicator extends StatelessWidget {
  const _TurnIndicator();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        decoration: BoxDecoration(
          color: PukHukTheme.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: PukHukTheme.primary, width: 1.5),
        ),
        child: Text(
          '▲  YOUR TURN  ▲',
          style: GoogleFonts.orbitron(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: PukHukTheme.primary,
            letterSpacing: 2,
          ),
        ),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .fade(begin: 1.0, end: 0.4, duration: 700.ms)
          .scale(
            begin: const Offset(1.0, 1.0),
            end: const Offset(1.02, 1.02),
            duration: 700.ms,
          ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waiting Overlay — shown before game starts
// ─────────────────────────────────────────────────────────────────────────────
class _WaitingOverlay extends StatelessWidget {
  const _WaitingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PukHukTheme.surface.withOpacity(0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WAITING FOR OPPONENT',
              style: GoogleFonts.orbitron(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: PukHukTheme.primary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: PukHukTheme.primary),
          ],
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(
          begin: 0.8,
          end: 1.0,
          duration: 1000.ms,
        );
  }
}
