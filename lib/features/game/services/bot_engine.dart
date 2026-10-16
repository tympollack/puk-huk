import 'dart:async';
import 'dart:math';

import 'package:flame/components.dart';
import '../../../data/models/game_session_model.dart';
import '../../../data/models/player_model.dart';

const String pukhukBotId = '00000000-0000-0000-0000-000000000000';

class BotEngine {
  final Random _rng = Random();

  BotEngine();

  /// Calculates the bot's throw impulse based on the current state and player skill
  Future<Vector2> calculateBotImpulse({
    required GameSessionState state,
    required PlayerModel localPlayer,
  }) async {

    // Seed RNG deterministically per turn so concurrent clients simulate identical trajectories
    final rng = Random(state.turnNumber.hashCode ^ localPlayer.uid.hashCode);

    // Simulate thinking delay (1.5s - 3s)
    final delayMs = 1500 + rng.nextInt(1500);
    await Future.delayed(Duration(milliseconds: delayMs));

    // Simple AI: aim for the 3-point zone (approx 0.25m from far edge)
    // Board is 0.56m wide, 3.66m long. Start is (0.28, 3.4). Target is (0.28, 0.25).
    double targetX = 0.28;
    double targetY = 0.25;

    // Calculate baseline vector
    double dx = targetX - 0.28;
    double dy = targetY - 3.4;

    // Perturbation based on player's unranked ELO
    // ELO 1000 = high variance, ELO 2000 = low variance
    double eloFactor = max(1000, min(2000, localPlayer.unrankedElo)).toDouble();
    double skillInverse = 1.0 - ((eloFactor - 1000) / 1000); // 1.0 at 1000, 0.0 at 2000
    
    // Add noise to the target based on skill
    double maxNoiseX = 0.4 * skillInverse; // up to 40cm off
    double maxNoiseY = 0.1 * skillInverse; // up to 10cm off
    
    dx += (maxNoiseX * rng.nextDouble()) - (maxNoiseX / 2);
    dy += (maxNoiseY * rng.nextDouble()) - (maxNoiseY / 2);

    // Baseline force calibrated for Forge2D linear damping (0.45 + low-speed damping)
    // to cleanly travel ~3.2m across the board into the scoring zones (maxLaunchImpulse is 0.06).
    double baseForce = 4.9;
    double forceNoise = 0.4 * skillInverse;
    double appliedForce = baseForce + ((rng.nextDouble() * forceNoise) - (forceNoise / 2));

    return Vector2(dx, dy)..normalize()..scale(appliedForce * 0.01);
  }
}
