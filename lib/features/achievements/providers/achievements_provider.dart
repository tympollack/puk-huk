import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/providers/auth_provider.dart';

part 'achievements_provider.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Achievement definition — static catalogue (could move to Firestore
// /config/achievements for remote updates without app release).
// ─────────────────────────────────────────────────────────────────────────────
class Achievement {
  final String id;
  final String title;
  final String description;
  final String iconName; // maps to a Material icon in the UI layer
  final int targetValue;
  final String statKey; // matches a PlayerModel field

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.iconName,
    required this.targetValue,
    required this.statKey,
  });
}

const List<Achievement> kAchievementCatalogue = [
  Achievement(
    id: 'first_win',
    title: 'First Blood',
    description: 'Win your first match',
    iconName: 'emoji_events',
    targetValue: 1,
    statKey: 'wins',
  ),
  Achievement(
    id: 'win_streak_5',
    title: 'On Fire',
    description: 'Win 5 matches in a row',
    iconName: 'whatshot',
    targetValue: 5,
    statKey: 'winStreak',
  ),
  Achievement(
    id: 'speed_demon',
    title: 'Speed Demon',
    description: 'Reach a puck speed of 4.0 m/s',
    iconName: 'speed',
    targetValue: 4,
    statKey: 'highestPuckSpeed',
  ),
  Achievement(
    id: 'sharpshooter',
    title: 'Sharpshooter',
    description: 'Score a hanger (overhang bonus)',
    iconName: 'gps_fixed',
    targetValue: 1,
    statKey: 'hangerCount', // tracked separately in match events
  ),
  Achievement(
    id: 'veteran',
    title: 'Veteran',
    description: 'Play 100 total matches',
    iconName: 'military_tech',
    targetValue: 100,
    statKey: 'totalGames',
  ),
  Achievement(
    id: 'gold_tier',
    title: 'Gold Standard',
    description: 'Reach Gold tier (1500 ELO)',
    iconName: 'workspace_premium',
    targetValue: 1500,
    statKey: 'elo',
  ),
  Achievement(
    id: 'diamond_tier',
    title: 'Diamond Elite',
    description: 'Reach Diamond tier (1800 ELO)',
    iconName: 'diamond',
    targetValue: 1800,
    statKey: 'elo',
  ),
  Achievement(
    id: 'distance_master',
    title: 'Distance Master',
    description: 'Land a throw at 3.4m+ distance',
    iconName: 'social_distance',
    targetValue: 3,
    statKey: 'longestPuckDistance',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Unlocked achievement IDs for current player (from PlayerModel.achievements)
// ─────────────────────────────────────────────────────────────────────────────
@riverpod
Set<String> unlockedAchievementIds(UnlockedAchievementIdsRef ref) {
  final player = ref.watch(currentPlayerProvider).valueOrNull;
  return player?.achievements.toSet() ?? {};
}
