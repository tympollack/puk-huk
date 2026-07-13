import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/models/game_session_model.dart';
import '../../../services/realtime_sync_service.dart';

part 'game_providers.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Live game session stream
// ─────────────────────────────────────────────────────────────────────────────
@riverpod
Stream<GameSessionState> gameSession(GameSessionRef ref, String sessionId) {
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
