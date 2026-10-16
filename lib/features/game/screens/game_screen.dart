import 'dart:async';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:vector_math/vector_math_64.dart' as vmath;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/puk_huk_theme.dart';
import '../../../data/models/game_session_model.dart';
import '../../../services/leaderboard_service.dart';
import '../../../services/realtime_sync_service.dart';
import '../../../services/matchmaking_service.dart';
import '../../../services/player_repository.dart';
import '../engine/board_boundary_component.dart';
import '../engine/aim_indicator_component.dart';
import '../engine/puck_component.dart';
import '../engine/puk_huk_game.dart';
import '../hud/game_hud_widget.dart';
import '../hud/minimap_widget.dart';
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
  PuckComponent? _botPuck;
  ProviderSubscription? _sessionSub;
  StreamSubscription? _presenceSub;
  Timer? _turnTimer;
  bool _gameOverDialogShown = false;

  @override
  void initState() {
    super.initState();
    _game = PukHukGame(
      onPuckSettled: _handlePuckSettled,
      onPuckLaunched: () {
        // Suspend the turn deadline while the puck is in motion
        _turnTimer?.cancel();
      },
      onTelemetryUpdate: (velocity, angle, spin, isAiming) {
        if (!mounted) return;
        ref.read(telemetryProvider.notifier).updateTelemetry(
          velocity: velocity,
          angle: angle,
          spin: spin,
          isAiming: isAiming,
        );
      },
    );
    
    // Initialize Presence
    Future.microtask(() {
      final player = ref.read(currentPlayerProvider).value;
      if (player != null) {
        ref.read(realtimeSyncServiceProvider).trackPresence(widget.sessionId, player.uid);
      }
      
      // Watch presence to handle disconnects
      _presenceSub = ref.read(realtimeSyncServiceProvider).watchPresence(widget.sessionId).listen((presenceState) {
        if (!mounted || player == null) return;
        final sessionState = ref.read(gameSessionProvider(widget.sessionId)).value;
        if (sessionState == null || sessionState.status == 'completed') return;
        
        final opponentId = sessionState.scores.keys.firstWhere((id) => id != player.uid, orElse: () => '');
        if (opponentId.isEmpty || opponentId == pukhukBotId) return;

        final oppPresence = presenceState[opponentId];
        if (oppPresence == null || (oppPresence is List && oppPresence.isEmpty)) {
          // Opponent went offline! Auto forfeit only if active and it is currently the opponent's turn
          if (sessionState.status == 'active' && sessionState.currentTurnPlayerId == opponentId) {
             _autoForfeitTurn(sessionState, opponentId, disconnect: true);
          }
        }
      });
    });

    // Listen to session to initialize bot if needed and handle turns
    _sessionSub = ref.listenManual(
      gameSessionProvider(widget.sessionId),
      (prev, next) {
        final state = next.value;
        if (state == null) return;
        
        final player = ref.read(currentPlayerProvider).value;
        if (player == null) return;

        // 0. Handle active/paused/completed states
        _game.isPaused = (state.status == 'paused');
        
        if (state.status != 'active') {
          _turnTimer?.cancel();
        }

        if (state.status == 'completed') {
          _showGameOverDialog(state);
          return;
        }

        if (state.status == 'paused') {
          // Check if we need to show a dialog
          final inactivePlayers = state.missedTurns.entries
            .where((MapEntry<String, int> e) => e.value >= 2)
            .map((e) => e.key);
          final inactivePlayerId = inactivePlayers.isNotEmpty ? inactivePlayers.first : null;
            
          if (inactivePlayerId != null && inactivePlayerId != player.uid) {
            // The OPPONENT is inactive. Show dialog to claim win.
            _showInactivityDialog(state);
          }
          return; // Pause the game loop
        }

        // 1. Initialize Bot if needed
        if (_botEngine == null && state.scores.containsKey(pukhukBotId)) {
          _botEngine = BotEngine();
        }

        // 2. Sync physics engine with the authoritative state
        _syncBoardState(state.boardState);

        // 3. Spawn puck if it is now a local turn (player or bot)
        final isMyTurn = state.currentTurnPlayerId == player.uid;
        final wasMyTurn = prev?.value?.currentTurnPlayerId == player.uid;
        final isBotTurn = state.currentTurnPlayerId == pukhukBotId;
        final wasBotTurn = prev?.value?.currentTurnPlayerId == pukhukBotId;
        
        if (state.status == 'active') {
          // Turn Timer Logic
          _turnTimer?.cancel();
          final isPuckInFlight = _game.inFlightPuck != null || (_game.activePuck?.isTracking ?? false);
          if (isMyTurn && !isPuckInFlight) {
            final startTime = state.turnStartedAt ?? DateTime.now();
            final elapsed = DateTime.now().difference(startTime.toLocal()).inSeconds;
            final remaining = 15 - elapsed;
            
            if (remaining <= 0) {
              _autoForfeitTurn(state, player.uid);
            } else {
              _turnTimer = Timer(Duration(seconds: remaining), () {
                if (mounted) _autoForfeitTurn(state, player.uid);
              });
            }
          }

          if (isMyTurn && _game.activePuck == null && !isPuckInFlight) {
            // Add a small delay to ensure physics world is fully loaded if this is the first turn
            Future.delayed(const Duration(milliseconds: 300), () {
              if (!mounted) return;
              if (isMyTurn && _game.activePuck == null && _game.inFlightPuck == null) {
                _game.spawnPuck(
                  ownerId: player.uid,
                  color: PukHukTheme.primary, // Local player color
                  puckId: const Uuid().v4(),
                );
              }
            });
          } else if (isBotTurn && !wasBotTurn && _botEngine != null) {
            _botEngine!.calculateBotImpulse(state: state, localPlayer: player).then((impulse) async {
              if (!mounted) return;
              
              final startPos = Vector2(PukHukGame.boardWidth / 2, PukHukGame.boardLength - 0.25);
              final botPuck = PuckComponent(
                puckId: Uuid().v4(),
                ownerId: pukhukBotId,
                color: PukHukTheme.secondary,
                radius: PukHukGame.puckRadius,
                friction: PukHukGame.puckFriction,
                restitution: PukHukGame.puckRestitution,
                linearDampingValue: PukHukGame.linearDamping,
                position: startPos,
              );
              _botPuck = botPuck;
              await _game.world.add(botPuck);
              
              // 1. Show aim indicator
              final aimIndicator = AimIndicatorComponent(puck: botPuck);
              _game.world.add(aimIndicator);
              
              // 2. Animate pullback over 1.5s
              final int steps = 30;
              final delayPerStep = 1500 ~/ steps;
              final dragDirection = -impulse.normalized();
              // Normalize the impulse magnitude to [0, 1] to calculate drag distance
              final magnitude = (impulse.length / PukHukGame.maxLaunchImpulse).clamp(0.0, 1.0);
              
              for (int i = 1; i <= steps; i++) {
                if (!mounted) return;
                double progress = i / steps;
                
                // Increase aim indicator strength
                botPuck.setAimImpulse(impulse * progress);
                
                // Physically pull puck backwards up to 0.5 meters
                final currentPos = startPos + (dragDirection * (progress * 0.5 * magnitude));
                // Clamp the Y position so it doesn't drag into the physical back rail
                currentPos.y = currentPos.y.clamp(0.0, PukHukGame.boardLength - PukHukGame.puckRadius - 0.02);
                botPuck.body.setTransform(currentPos, 0);
                
                await Future.delayed(Duration(milliseconds: delayPerStep));
              }
              
              // 3. Hold for 1 second
              await Future.delayed(const Duration(seconds: 1));
              
              if (!mounted) return;
              
              // 4. Release and Shoot
              aimIndicator.removeFromParent();
              botPuck.setAimImpulse(Vector2.zero());
              botPuck.body.applyLinearImpulse(impulse);
              botPuck.startTracking(onSettled: () {
                _handlePuckSettled(botPuck);
              });
            });
          }
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _sessionSub?.close();
    _presenceSub?.cancel();
    _turnTimer?.cancel();
    _botPuck = null;
    super.dispose();
  }

  Future<void> _autoForfeitTurn(GameSessionState currentState, String playerId, {bool disconnect = false}) async {
    if (!mounted) return;
    
    // Validate live session state and turn ownership
    final latestState = ref.read(gameSessionProvider(widget.sessionId)).value;
    if (latestState == null ||
        latestState.status != 'active' ||
        latestState.currentTurnPlayerId != playerId ||
        latestState.turnNumber != currentState.turnNumber) {
      return;
    }

    // Cancel active puck and reset aiming state so future spawns work
    _game.cancelActivePuck();
    if (_botPuck != null) {
      if (_botPuck!.isMounted) _botPuck!.removeFromParent();
      _botPuck = null;
    }

    // Increment missed turns for this player
    final newMissedTurns = Map<String, int>.from(latestState.missedTurns);
    newMissedTurns[playerId] = disconnect ? 2 : ((newMissedTurns[playerId] ?? 0) + 1);
    
    // Determine if game should pause (2 misses)
    final shouldPause = (newMissedTurns[playerId] ?? 0) >= 2;
    final opponentId = latestState.scores.keys.firstWhere((id) => id != playerId);
    
    var nextTurnPlayerId = shouldPause ? latestState.currentTurnPlayerId : opponentId;
    var nextTurnNumber = latestState.turnNumber + 1;
    var nextBoardState = latestState.boardState;
    var newScores = Map<String, int>.from(latestState.scores);
    var status = shouldPause ? 'paused' : 'active';

    // If turn 8 expires, the round is over! Calculate round scoring just like settled puck
    if (latestState.turnNumber == 8) {
      final roundResult = _calculateRoundEnd(
        pucks: latestState.boardState,
        currentScores: latestState.scores,
        lastTurnPlayerId: playerId,
        opponentId: opponentId,
      );
      newScores = roundResult.scores;
      nextBoardState = roundResult.boardState;
      nextTurnNumber = roundResult.nextTurnNumber;
      nextTurnPlayerId = roundResult.nextTurnPlayerId;
      if (roundResult.isCompleted) {
        status = 'completed';
      } else {
        final currentPucks = _game.world.children.whereType<PuckComponent>().toList();
        for (final p in currentPucks) {
          p.removeFromParent();
        }
      }
    }

    final newState = latestState.copyWith(
      turnNumber: nextTurnNumber,
      currentTurnPlayerId: nextTurnPlayerId,
      turnStartedAt: DateTime.now().toUtc(),
      missedTurns: newMissedTurns,
      status: status,
      scores: newScores,
      boardState: nextBoardState,
    );

    try {
      await ref.read(realtimeSyncServiceProvider).submitTurn(
        matchId: widget.sessionId,
        playerId: playerId,
        expectedTurnNumber: latestState.turnNumber,
        newState: newState,
      );

      if (status == 'completed') {
        _resolveCompletedMatch(newState);
      }
    } catch (e) {
      print('Auto-forfeit failed: $e');
    }
  }

  void _showInactivityDialog(GameSessionState state) {
    if (!mounted) return;
    
    // Prevent multiple dialogs
    if (ModalRoute.of(context)?.isCurrent != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return _InactivityDialogContent(
              state: state,
              sessionId: widget.sessionId,
            );
          }
        );
      }
    );
  }

  void _syncBoardState(List<PuckStateModel> boardState) {
    // Get all current pucks in the physics world
    final currentPucks = _game.world.children.whereType<PuckComponent>().toList();
    
    // Remove pucks that no longer exist in the authoritative state
    // Protect active puck, in-flight pucks, and bot puck currently in motion/aiming
    for (final puck in currentPucks) {
      if (puck == _game.activePuck ||
          puck == _game.inFlightPuck ||
          puck.isTracking ||
          puck == _botPuck) {
        continue;
      }
      final existsInState = boardState.any((p) => p.puckId == puck.puckId);
      if (!existsInState) {
        puck.removeFromParent();
      }
    }

    // Add or update pucks from the authoritative state
    for (final pState in boardState) {
      final existingPuck = currentPucks.where((p) => p.puckId == pState.puckId).firstOrNull;
      
      if (existingPuck != null) {
        if (existingPuck != _game.activePuck &&
            existingPuck != _game.inFlightPuck &&
            !existingPuck.isTracking &&
            existingPuck != _botPuck) {
          // Update position for settled pucks
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

  ({
    Map<String, int> scores,
    List<PuckStateModel> boardState,
    int nextTurnNumber,
    String nextTurnPlayerId,
    bool isCompleted,
  }) _calculateRoundEnd({
    required List<PuckStateModel> pucks,
    required Map<String, int> currentScores,
    required String lastTurnPlayerId,
    required String opponentId,
  }) {
    final newScores = Map<String, int>.from(currentScores);
    final validPucks = pucks
        .where((p) => p.status != 'knocked_off')
        .toList()
      ..sort((a, b) => a.y.compareTo(b.y));

    if (validPucks.isNotEmpty) {
      final winningPuck = validPucks.first;
      final roundWinnerId = winningPuck.ownerId;

      final bestOpponentPuck = validPucks.where((p) => p.ownerId != roundWinnerId).firstOrNull;
      final cutoffY = bestOpponentPuck?.y ?? PukHukGame.boardLength;

      int roundScore = 0;
      for (final p in validPucks.where((p) => p.ownerId == roundWinnerId)) {
        if (p.y < cutoffY) {
          final zone = BoardBoundaryComponent.zoneForPosition(p.y, PukHukGame.boardLength);
          roundScore += ScoringZones.pointsForZone(zone, isHanger: zone == -1);
        }
      }

      newScores[roundWinnerId] = (newScores[roundWinnerId] ?? 0) + roundScore;
    }

    // Shuffleboard regulation victory target is 15 points
    const winningScore = 15;
    final p1Score = newScores[lastTurnPlayerId] ?? 0;
    final p2Score = newScores[opponentId] ?? 0;
    final isCompleted = p1Score >= winningScore || p2Score >= winningScore;

    if (isCompleted) {
      final winnerId = p1Score >= p2Score ? lastTurnPlayerId : opponentId;
      return (
        scores: newScores,
        boardState: pucks,
        nextTurnNumber: 8,
        nextTurnPlayerId: winnerId,
        isCompleted: true,
      );
    }

    return (
      scores: newScores,
      boardState: <PuckStateModel>[],
      nextTurnNumber: 1,
      nextTurnPlayerId: lastTurnPlayerId,
      isCompleted: false,
    );
  }

  Future<void> _resolveCompletedMatch(GameSessionState finalState) async {
    final player = ref.read(currentPlayerProvider).value;
    if (player == null) return;
    final opponentId = finalState.scores.keys.firstWhere((id) => id != player.uid, orElse: () => '');
    if (opponentId.isEmpty) return;

    final myScore = finalState.scores[player.uid] ?? 0;
    final oppScore = finalState.scores[opponentId] ?? 0;
    final winnerId = myScore >= oppScore ? player.uid : opponentId;
    final loserId = winnerId == player.uid ? opponentId : player.uid;

    final matchmaking = ref.read(matchmakingServiceProvider);
    try {
      if (opponentId == pukhukBotId) {
        await matchmaking.resolveUnrankedMatch(
          matchId: widget.sessionId,
          winnerId: winnerId,
          loserId: loserId,
          winnerElo: winnerId == player.uid ? player.elo : 1200,
          loserElo: loserId == player.uid ? player.elo : 1200,
          winnerGamesPlayed: winnerId == player.uid ? player.totalGames : 0,
          loserGamesPlayed: loserId == player.uid ? player.totalGames : 0,
          winnerScore: finalState.scores[winnerId] ?? 0,
          loserScore: finalState.scores[loserId] ?? 0,
        );
        ref.invalidate(currentPlayerProvider);
        ref.invalidate(globalLeaderboardProvider);
      } else {
        final oppPlayer = await ref.read(playerRepositoryProvider).getPlayer(opponentId);
        final oppElo = oppPlayer?.elo ?? 1200;
        final oppGames = oppPlayer?.totalGames ?? 0;

        // Fetch authoritative match_id from game_sessions table
        String targetMatchId = widget.sessionId;
        try {
          final sessionRow = await Supabase.instance.client
              .schema('pukhuk')
              .from('game_sessions')
              .select('match_id')
              .eq('id', widget.sessionId)
              .maybeSingle();
          if (sessionRow != null && sessionRow['match_id'] != null) {
            targetMatchId = sessionRow['match_id'] as String;
          }
        } catch (_) {}

        await matchmaking.resolveMatch(
          matchId: targetMatchId,
          winnerId: winnerId,
          loserId: loserId,
          winnerElo: winnerId == player.uid ? player.elo : oppElo,
          loserElo: loserId == player.uid ? player.elo : oppElo,
          winnerGamesPlayed: winnerId == player.uid ? player.totalGames : oppGames,
          loserGamesPlayed: loserId == player.uid ? player.totalGames : oppGames,
          winnerScore: finalState.scores[winnerId] ?? 0,
          loserScore: finalState.scores[loserId] ?? 0,
        );

        ref.invalidate(currentPlayerProvider);
        ref.invalidate(globalLeaderboardProvider);
      }
    } catch (e) {
      print('Could not resolve match record: $e');
    }
  }

  void _showGameOverDialog(GameSessionState state) {
    if (!mounted || _gameOverDialogShown) return;
    _gameOverDialogShown = true;

    final player = ref.read(currentPlayerProvider).value;
    final myScore = (player != null ? state.scores[player.uid] : null) ?? 0;
    final opponentId = state.scores.keys.firstWhere((id) => id != player?.uid, orElse: () => '');
    final oppScore = state.scores[opponentId] ?? 0;
    final isWinner = myScore >= oppScore;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF161A22),
          title: Text(
            isWinner ? 'VICTORY!' : 'DEFEAT',
            style: TextStyle(
              color: isWinner ? PukHukTheme.primary : PukHukTheme.danger,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Final Score: $myScore - $oppScore',
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                isWinner ? 'Congratulations, you won the match!' : 'Good game! Better luck next time.',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                context.go(Routes.lobby);
              },
              child: const Text('RETURN TO LOBBY', style: TextStyle(color: PukHukTheme.primary, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  void _handlePuckSettled(PuckComponent puck) async {
    if (puck == _botPuck) {
      _botPuck = null;
    }

    final player = ref.read(currentPlayerProvider).value;
    final currentState = ref.read(gameSessionProvider(widget.sessionId)).value;
    
    if (player == null || currentState == null) return;
    
    // Only the local player OR the local bot should process settlements
    if (currentState.currentTurnPlayerId != player.uid && 
        currentState.currentTurnPlayerId != pukhukBotId) {
      return;
    }

    // Collect all pucks currently on the board
    final currentPucks = _game.world.children.whereType<PuckComponent>().toList();
    
    final newBoardState = <PuckStateModel>[];
    
    for (final p in currentPucks) {
      // Add to state regardless of status to maintain object permanence
      newBoardState.add(PuckStateModel(
        puckId: p.puckId,
        ownerId: p.ownerId,
        x: p.body.position.x,
        y: p.body.position.y,
        status: p.status,
      ));
    }

    final opponentId = currentState.scores.keys.firstWhere((id) => id != player.uid);
    var nextTurnPlayerId = currentState.currentTurnPlayerId == player.uid ? opponentId : player.uid;
    var nextTurnNumber = currentState.turnNumber + 1;
    var nextBoardState = newBoardState;
    var newScores = Map<String, int>.from(currentState.scores);
    var newMissedTurns = Map<String, int>.from(currentState.missedTurns);
    newMissedTurns[currentState.currentTurnPlayerId] = 0; // Reset missed turns on a successful throw
    var status = currentState.status;

    // If this was the 8th throw, the round is over! Calculate cancellation scoring.
    if (currentState.turnNumber == 8) {
      final roundResult = _calculateRoundEnd(
        pucks: newBoardState,
        currentScores: newScores,
        lastTurnPlayerId: currentState.currentTurnPlayerId,
        opponentId: opponentId,
      );
      newScores = roundResult.scores;
      nextBoardState = roundResult.boardState;
      nextTurnNumber = roundResult.nextTurnNumber;
      nextTurnPlayerId = roundResult.nextTurnPlayerId;
      if (roundResult.isCompleted) {
        status = 'completed';
      } else {
        // Clear board visually for new round
        for (final p in currentPucks) {
          p.removeFromParent();
        }
      }
    }

    final newState = currentState.copyWith(
      turnNumber: nextTurnNumber,
      currentTurnPlayerId: nextTurnPlayerId,
      turnStartedAt: DateTime.now().toUtc(),
      scores: newScores,
      boardState: nextBoardState,
      missedTurns: newMissedTurns,
      status: status,
      lastAction: ActionModel(
        playerId: currentState.currentTurnPlayerId,
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

      if (status == 'completed') {
        _resolveCompletedMatch(newState);
      }
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
            // ── Background Stadium ───────────────────────────────────────
            Positioned.fill(
              child: Transform.translate(
                offset: const Offset(0, -20), // Shifted down 130px from -150
                child: Image.asset(
                  'assets/images/stadium_bg.jpg',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),

            // ── Physics canvas ──────────────────────────────────────────
            Positioned(
              top: 130, // Shifted down 130px to match background image
              left: 0,
              right: 0,
              bottom: (MediaQuery.of(context).size.height * 0.30) - 130, // Preserve exact original bounds, just shifted
              child: Transform(
                alignment: FractionalOffset.bottomCenter,
                transform: vmath.Matrix4.identity()
                  ..setEntry(3, 2, 0.001) // Perspective projection
                  ..translate(0.0, -70.0, 0.0) // Original perfect alignment mapping
                  ..rotateX(-0.95) // Adjust tilt to match image perspective
                  ..scale(3.2, 3.2, 1.0), // Scale up to match lane width
                child: GameWidget(game: _game),
              ),
            ),

            // ── HUD overlay ──────────────────────────────────────────────
            if (player != null)
              Positioned.fill(
                child: GameHudWidget(
                  sessionId: widget.sessionId,
                  localPlayerId: player.uid,
                ),
              ),

            // ── Minimap (Jumbotron) ──────────────────────────────────────
            Positioned(
              top: MediaQuery.of(context).size.height * 0.08, // Down ~8-10%
              left: 0,
              right: 0,
              child: Transform.scale(
                scale: 0.90, // Shrink Jumbotron slightly less
                child: Center(
                  child: Consumer(
                    builder: (context, ref, _) {
                      final sessionState = ref.watch(gameSessionProvider(widget.sessionId)).value;
                      return MinimapWidget(
                        sessionId: widget.sessionId,
                        onPuckSelect: (id) {},
                        themeId: sessionState?.themeId ?? 'cyberpunk',
                        game: _game,
                      );
                    }
                  ),
                ),
              ),
            ),

            // ── Exit button ──────────────────────────────────────────────
            Positioned(
              top: 10,
              left: 10,
              child: InkWell(
                onTap: () {
                  _confirmExit(context);
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161A22).withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF30363D), width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 8),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                    ],
                  ),
                ),
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

class _InactivityDialogContent extends ConsumerStatefulWidget {
  final GameSessionState state;
  final String sessionId;
  
  const _InactivityDialogContent({required this.state, required this.sessionId});

  @override
  ConsumerState<_InactivityDialogContent> createState() => _InactivityDialogContentState();
}

class _InactivityDialogContentState extends ConsumerState<_InactivityDialogContent> {
  late Timer _timer;
  int _secondsLeft = 30;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Color(0xFF161A22),
      title: Text('Opponent Inactive', style: TextStyle(color: Colors.white)),
      content: Text('Your opponent has missed 2 turns or gone offline.\nYou can claim the win in $_secondsLeft seconds.', style: TextStyle(color: Colors.white70)),
      actions: [
        TextButton(
          onPressed: () {
            // Resume and give them another chance (reset missed turns)
            Navigator.pop(context);
            final newState = widget.state.copyWith(
              status: 'active',
              missedTurns: {},
              turnStartedAt: DateTime.now().toUtc(),
            );
            ref.read(realtimeSyncServiceProvider).submitTurn(
              matchId: widget.sessionId,
              playerId: ref.read(currentPlayerProvider).value!.uid,
              expectedTurnNumber: widget.state.turnNumber,
              newState: newState,
            );
          },
          child: Text('WAIT', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: _secondsLeft > 0 ? null : () async {
            // Claim win
            Navigator.pop(context);
            final latestState = ref.read(gameSessionProvider(widget.sessionId)).value ?? widget.state;
            final player = ref.read(currentPlayerProvider).value;
            if (player == null) return;

            final opponentId = latestState.scores.keys.firstWhere((id) => id != player.uid, orElse: () => '');
            // Guard: Only allow claiming win if opponent has at least 2 missed turns and game is paused
            final opponentMissed = latestState.missedTurns[opponentId] ?? 0;
            if (opponentMissed < 2 || latestState.status != 'paused') {
              return;
            }

            final newScores = Map<String, int>.from(latestState.scores);
            newScores[player.uid] = 15; // Auto win
            
            final newState = latestState.copyWith(
              status: 'completed',
              scores: newScores,
            );
            await ref.read(realtimeSyncServiceProvider).submitTurn(
              matchId: widget.sessionId,
              playerId: player.uid,
              expectedTurnNumber: latestState.turnNumber,
              newState: newState,
            );
          },
          child: Text('CLAIM WIN', style: TextStyle(color: _secondsLeft > 0 ? Colors.white24 : PukHukTheme.primary, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
