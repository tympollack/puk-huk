import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/models/game_session_model.dart';
import '../../../services/realtime_sync_service.dart';

part 'game_providers.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Live game session stream
// ─────────────────────────────────────────────────────────────────────────────
@riverpod
Stream<GameSessionState> gameSession(Ref ref, String sessionId) {
  final sync = ref.watch(realtimeSyncServiceProvider);
  return sync.watchSession(sessionId);
}

// ─────────────────────────────────────────────────────────────────────────────
// Shuffleboard scoring zones — standard 4-zone layout
// ─────────────────────────────────────────────────────────────────────────────
abstract class ScoringZones {
  static const Map<int, int> zonePoints = {
    1: 1,
    2: 2,
    3: 3,
    4: 4,
  };
  static const int hangerBonus = 5;
  static const int foulPenalty = -1; // puck knocked off / out of bounds

  static int pointsForZone(int zone, {bool isHanger = false}) {
    if (isHanger) return hangerBonus;
    return zonePoints[zone] ?? 0;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live Telemetry Stream (Flame -> UI Bridge)
// ─────────────────────────────────────────────────────────────────────────────
class TelemetryState {
  final double velocity; // m/s
  final double angle;    // degrees
  final double spin;     // RPS
  final bool isAiming;

  const TelemetryState({
    this.velocity = 0.0,
    this.angle = 0.0,
    this.spin = 0.0,
    this.isAiming = false,
  });
}

@riverpod
class Telemetry extends _$Telemetry {
  @override
  TelemetryState build() => const TelemetryState();

  void updateTelemetry({
    required double velocity,
    required double angle,
    required double spin,
    required bool isAiming,
  }) {
    state = TelemetryState(
      velocity: velocity,
      angle: angle,
      spin: spin,
      isAiming: isAiming,
    );
  }

  void reset() {
    state = const TelemetryState();
  }
}
