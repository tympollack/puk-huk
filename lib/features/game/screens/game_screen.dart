import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/puk_huk_theme.dart';
import '../../../data/models/game_session_model.dart';
import '../../../services/realtime_sync_service.dart';
import '../engine/board_boundary_component.dart';
import '../engine/puck_component.dart';
import '../engine/puk_huk_game.dart';
import '../hud/game_hud_widget.dart';
import '../providers/game_providers.dart';
import '../services/bot_engine.dart';

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
  BotEngine? _botEngine;
  ProviderSubscription? _sessionSub;

  @override
  void initState() {
    super.initState();
    _game = PukHukGame(
      onPuckSettled: _handlePuckSettled,
    );
    
    // Listen to session to initialize bot if needed and handle turns
    _sessionSub = ref.listenManual(
      gameSessionProvider(widget.sessionId),
      (prev, next) {
        final state = next.value;
        if (state == null) return;
        
        final player = ref.read(currentPlayerProvider).value;
        if (player == null) return;

        // 1. Initialize Bot if needed
        if (_botEngine == null && state.scores.containsKey(pukhukBotId)) {
          _botEngine = BotEngine(ref, widget.sessionId, player);
          _botEngine!.start();
        }

        // 2. Sync physics engine with the authoritative state
        _syncBoardState(state.boardState);

        // 3. Spawn puck if it is now the local player's turn
        final isMyTurn = state.currentTurnPlayerId == player.uid;
        final wasMyTurn = prev?.value?.currentTurnPlayerId == player.uid;
        
        if (isMyTurn && !wasMyTurn && state.status == 'active') {
          // Add a small delay to ensure physics world is fully loaded if this is the first turn
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;
            _game.spawnPuck(
              ownerId: player.uid,
              color: PukHukTheme.primary, // Local player color
              puckId: Uuid().v4(),
            );
          });
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _sessionSub?.close();
    _botEngine?.stop();
    super.dispose();
  }

  void _syncBoardState(List<PuckStateModel> boardState) {
    // Get all current pucks in the physics world
    final currentPucks = _game.world.children.whereType<PuckComponent>().toList();
    
    // Remove pucks that no longer exist in the authoritative state
    // (e.g. they were knocked off the board)
    for (final puck in currentPucks) {
      if (puck == _game.activePuck) continue; // Don't touch the active puck we are throwing
      final existsInState = boardState.any((p) => p.puckId == puck.puckId);
      if (!existsInState) {
        puck.removeFromParent();
      }
    }

    // Add or update pucks from the authoritative state
    for (final pState in boardState) {
      final existingPuck = currentPucks.where((p) => p.puckId == pState.puckId).firstOrNull;
      
      if (existingPuck != null) {
        if (existingPuck != _game.activePuck) {
          // Update position for opponent pucks that might have settled
          existingPuck.body.setTransform(Vector2(pState.x, pState.y), 0);
        }
      } else {
        // Spawn a new puck that arrived from the state (e.g. opponent threw it)
        final newPuck = PuckComponent(
          puckId: pState.puckId,
          ownerId: pState.ownerId,
          color: pState.ownerId == pukhukBotId ? PukHukTheme.secondary : (pState.ownerId == ref.read(currentPlayerProvider).value?.uid ? PukHukTheme.primary : PukHukTheme.secondary),
          radius: PukHukGame.puckRadius,
          friction: PukHukGame.puckFriction,
          restitution: PukHukGame.puckRestitution,
          linearDampingValue: PukHukGame.linearDamping,
          position: Vector2(pState.x, pState.y),
          status: pState.status,
        );
        _game.world.add(newPuck);
      }
    }
  }

  void _handlePuckSettled(PuckComponent puck) async {
    final player = ref.read(currentPlayerProvider).value;
    final currentState = ref.read(gameSessionProvider(widget.sessionId)).value;
    
    if (player == null || currentState == null) return;
    if (currentState.currentTurnPlayerId != player.uid) return;

    // Collect all pucks currently on the board
    final currentPucks = _game.world.children.whereType<PuckComponent>().toList();
    
    final newBoardState = <PuckStateModel>[];
    int playerRoundScore = 0;
    int opponentRoundScore = 0;
    
    for (final p in currentPucks) {
      final xPos = p.body.position.x;
      
      String status = 'active';
      int pts = 0;
      
      // If the puck fell off the board (xPos > boardLength), it's dead (0 points)
      if (xPos > PukHukGame.boardLength + 0.1 || xPos < -0.1) {
        status = 'knocked_off';
      } else {
        final zone = BoardBoundaryComponent.zoneForPosition(xPos, PukHukGame.boardLength);
        pts = ScoringZones.pointsForZone(zone, isHanger: zone == -1);
      }
      
      // Add to state regardless of status to maintain object permanence
      newBoardState.add(PuckStateModel(
        puckId: p.puckId,
        ownerId: p.ownerId,
        x: p.body.position.x,
        y: p.body.position.y,
        status: status,
      ));
      
      if (p.ownerId == player.uid) {
        playerRoundScore += pts;
      } else {
        opponentRoundScore += pts;
      }
    }

    final xPos = puck.body.position.x;
    final zone = BoardBoundaryComponent.zoneForPosition(xPos, PukHukGame.boardLength);
    final pointsScored = ScoringZones.pointsForZone(zone, isHanger: zone == -1);
    
    final opponentId = currentState.scores.keys.firstWhere((id) => id != player.uid);

    final newState = currentState.copyWith(
      turnNumber: currentState.turnNumber + 1,
      currentTurnPlayerId: opponentId,
      boardState: newBoardState,
      lastAction: ActionModel(
        playerId: player.uid,
        vectorX: puck.body.linearVelocity.x,
        vectorY: puck.body.linearVelocity.y,
        rotation: puck.body.angularVelocity,
        force: puck.peakSpeed,
        timestamp: DateTime.now(),
      ),
    );

    try {
      await ref.read(realtimeSyncServiceProvider).submitTurn(
        matchId: widget.sessionId,
        playerId: player.uid,
        expectedTurnNumber: currentState.turnNumber,
        newState: newState,
      );
    } catch (e) {
      print('Failed to submit turn: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(currentPlayerProvider).value;

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
              context.go(Routes.lobby);
            },
            child: const Text('Forfeit', style: TextStyle(color: PukHukTheme.danger)),
          ),
        ],
      ),
    );
  }
}
