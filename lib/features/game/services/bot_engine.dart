import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../services/realtime_sync_service.dart';
import '../providers/game_providers.dart';
import '../../../data/models/game_session_model.dart';
import '../../../data/models/player_model.dart';

const String pukhukBotId = '00000000-0000-0000-0000-000000000000';

class BotEngine {
  final WidgetRef ref;
  final String sessionId;
  final PlayerModel localPlayer;

  ProviderSubscription? _subscription;
  bool _isTakingTurn = false;
  final Random _rng = Random();

  BotEngine(this.ref, this.sessionId, this.localPlayer);

  void start() {
    _subscription = ref.listenManual<AsyncValue<GameSessionState>>(
      gameSessionProvider(sessionId),
      (previous, next) {
        final state = next.value;
        if (state == null) return;

        if (state.currentTurnPlayerId == pukhukBotId && !_isTakingTurn) {
          _takeTurn(state);
        }
      },
      fireImmediately: true,
    );
  }

  void stop() {
    _subscription?.close();
  }

  Future<void> _takeTurn(GameSessionState state) async {
    _isTakingTurn = true;

    // Simulate thinking delay (1.5s - 3s)
    final delayMs = 1500 + _rng.nextInt(1500);
    await Future.delayed(Duration(milliseconds: delayMs));

    // Simple AI: aim for the 3-point zone (approx 3.4m from start)
    // Board is 3.66m x 0.56m. Start is (0.25, 0.28). Target is (3.4, 0.28).
    double targetX = 3.4;
    double targetY = 0.28;

    // Calculate baseline vector
    double dx = targetX - 0.25;
    double dy = targetY - 0.28;

    // Perturbation based on player's unranked ELO
    // ELO 1000 = high variance, ELO 2000 = low variance
    double eloFactor = max(1000, min(2000, localPlayer.unrankedElo)).toDouble();
    double skillInverse = 1.0 - ((eloFactor - 1000) / 1000); // 1.0 at 1000, 0.0 at 2000
    
    // Add noise to the target based on skill
    double maxNoiseX = 0.4 * skillInverse; // up to 40cm off
    double maxNoiseY = 0.1 * skillInverse; // up to 10cm off
    
    dx += (maxNoiseX * _rng.nextDouble()) - (maxNoiseX / 2);
    dy += (maxNoiseY * _rng.nextDouble()) - (maxNoiseY / 2);

    // Baseline force required to reach 3.4m (heuristic approximation)
    double baseForce = 7.5;
    double forceNoise = 1.5 * skillInverse;
    double appliedForce = baseForce + ((_rng.nextDouble() * forceNoise) - (forceNoise / 2));

    // Construct the bot's turn action
    final action = ActionModel(
      playerId: pukhukBotId,
      vectorX: dx,
      vectorY: dy,
      rotation: 0,
      force: appliedForce,
      timestamp: DateTime.now(),
    );

    // Simplified kinematic destination
    double finalX = 0.25 + dx;
    double finalY = 0.28 + dy;
    
    // Clamp to board boundaries
    finalX = max(0.038, min(3.66 - 0.038, finalX));
    finalY = max(0.038, min(0.56 - 0.038, finalY));

    // Create a new puck
    final newPuck = PuckStateModel(
      puckId: const Uuid().v4(),
      ownerId: pukhukBotId,
      x: finalX,
      y: finalY,
      status: 'active',
    );

    final newBoard = List<PuckStateModel>.from(state.boardState)..add(newPuck);
    
    final newState = state.copyWith(
      turnNumber: state.turnNumber + 1,
      currentTurnPlayerId: localPlayer.uid,
      lastAction: action,
      boardState: newBoard,
    );

    try {
      await ref.read(realtimeSyncServiceProvider).submitTurn(
        matchId: sessionId, // matchId is same as sessionId for bot matches
        playerId: pukhukBotId,
        expectedTurnNumber: state.turnNumber,
        newState: newState,
      );
    } catch (e) {
      print('Bot failed to submit turn: $e');
    }

    _isTakingTurn = false;
  }
}
