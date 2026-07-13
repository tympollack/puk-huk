import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/theme/puk_huk_theme.dart';
import '../engine/board_boundary_component.dart';
import '../engine/puck_component.dart';
import '../engine/puk_huk_game.dart';
import '../hud/game_hud_widget.dart';
import '../providers/game_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GameScreen — fullscreen Flame canvas + HUD overlay + RTDB sync wiring.
// ─────────────────────────────────────────────────────────────────────────────
class GameScreen extends ConsumerStatefulWidget {
  final String sessionId;
  const GameScreen({super.key, required this.sessionId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  late final PukHukGame _game;

  @override
  void initState() {
    super.initState();
    _game = PukHukGame(
      onPuckSettled: _handlePuckSettled,
    );
  }

  void _handlePuckSettled(PuckComponent puck) {
    final player = ref.read(currentPlayerProvider).valueOrNull;
    if (player == null) return;

    // The puck's position is relative to the board centre, but zoneForPosition 
    // expects 0 to be the launch end and boardLength to be the far end.
    // In PukHukGame, the board is drawn from (0,0) to (boardLength, width).
    // The puck's x position maps directly to the distance along the board.
    final xPos = puck.body.position.x;
    final zone = BoardBoundaryComponent.zoneForPosition(xPos, PukHukGame.boardLength);
    final pointsScored = ScoringZones.pointsForZone(zone, isHanger: zone == -1);

    ref
        .read(turnStatsControllerProvider(widget.sessionId, player.uid).notifier)
        .recordPuckResult(
          speed: puck.peakSpeed,
          distance: puck.totalDistance,
          pointsScored: pointsScored,
        );
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(currentPlayerProvider).valueOrNull;

    return Scaffold(
      backgroundColor: PukHukTheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Physics canvas ──────────────────────────────────────────
            Positioned.fill(
              child: GameWidget(game: _game),
            ),

            // ── HUD overlay ──────────────────────────────────────────────
            if (player != null)
              Positioned.fill(
                child: GameHudWidget(
                  sessionId: widget.sessionId,
                  localPlayerId: player.uid,
                ),
              ),

            // ── Exit button ──────────────────────────────────────────────
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: PukHukTheme.textSecondary),
                onPressed: () => _confirmExit(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmExit(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PukHukTheme.cardBg,
        title: const Text('Leave match?'),
        content: const Text(
          'Leaving now will count as a forfeit and affect your ELO rating.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: const Text('Forfeit', style: TextStyle(color: PukHukTheme.danger)),
          ),
        ],
      ),
    );
  }
}
