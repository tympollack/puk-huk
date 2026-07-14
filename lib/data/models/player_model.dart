import 'package:freezed_annotation/freezed_annotation.dart';

part 'player_model.freezed.dart';
part 'player_model.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlayerModel — composite of hub profile (display_name) + game profile (ELO etc.)
//
// Hub:  Supabase `profiles` table        → display_name
// Game: Supabase `puk_huk_players` table → ELO, tier, stats, achievements
//
// The `uid` field is the auth.users.id (the Supabase Auth UID). All session
// references (game_sessions.player1_id etc.) use this same auth UID.
// ─────────────────────────────────────────────────────────────────────────────
@freezed
abstract class PlayerModel with _$PlayerModel {
  const PlayerModel._();

  const factory PlayerModel({
    required String uid,          // auth.users.id — auth UID
    required String displayName,  // from hub profiles.display_name

    // ── ELO & Ranking ────────────────────────────────────────────────────
    @Default(1000) int elo,
    @Default('bronze') String tier,

    // ── Match Record ─────────────────────────────────────────────────────
    @Default(0) int wins,
    @Default(0) int losses,
    @Default(0) int totalGames,
    @Default(0) int winStreak,
    @Default(0) int bestWinStreak,

    // ── Shuffleboard Performance Stats ───────────────────────────────────
    @Default(0.0) double highestPuckSpeed,
    @Default(0.0) double longestPuckDistance,
    @Default(0) int totalPucksThrown,

    // ── Social / Meta ────────────────────────────────────────────────────
    @Default([]) List<String> achievements,
    @Default(false) bool isOnline,
    DateTime? createdAt,
    DateTime? lastSeen,
  }) = _PlayerModel;

  factory PlayerModel.fromJson(Map<String, dynamic> json) =>
      _$PlayerModelFromJson(json);

  /// Build from a `puk_huk_players` row (display_name already denormalised).
  factory PlayerModel.fromSupabase(Map<String, dynamic> row) {
    return PlayerModel(
      uid: row['auth_uid'] as String,
      displayName: row['display_name'] as String? ?? 'Player',
      elo: row['elo'] as int? ?? 1000,
      tier: row['tier'] as String? ?? 'bronze',
      wins: row['wins'] as int? ?? 0,
      losses: row['losses'] as int? ?? 0,
      totalGames: row['total_games'] as int? ?? 0,
      winStreak: row['win_streak'] as int? ?? 0,
      bestWinStreak: row['best_win_streak'] as int? ?? 0,
      highestPuckSpeed:
          (row['highest_puck_speed'] as num?)?.toDouble() ?? 0.0,
      longestPuckDistance:
          (row['longest_puck_distance'] as num?)?.toDouble() ?? 0.0,
      totalPucksThrown: row['total_pucks_thrown'] as int? ?? 0,
      achievements:
          (row['achievements'] as List?)?.cast<String>() ?? const [],
      isOnline: row['is_online'] as bool? ?? false,
      createdAt: row['created_at'] != null
          ? DateTime.tryParse(row['created_at'] as String)
          : null,
      lastSeen: row['last_seen'] != null
          ? DateTime.tryParse(row['last_seen'] as String)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ELO tier helpers
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, int> kEloTiers = {
  'bronze': 0,
  'silver': 1200,
  'gold': 1500,
  'diamond': 1800,
};

String getTierForElo(int elo) {
  if (elo >= 1800) return 'diamond';
  if (elo >= 1500) return 'gold';
  if (elo >= 1200) return 'silver';
  return 'bronze';
}

// ─────────────────────────────────────────────────────────────────────────────
// LeaderboardEntry — lightweight read model for leaderboard queries.
// Built from puk_huk_players rows (display_name already embedded).
// ─────────────────────────────────────────────────────────────────────────────
@freezed
abstract class LeaderboardEntry with _$LeaderboardEntry {
  const LeaderboardEntry._();

  const factory LeaderboardEntry({
    required String uid,
    required String displayName,
    required int elo,
    required int wins,
    required String tier,
    @Default(0) int rank,
  }) = _LeaderboardEntry;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      _$LeaderboardEntryFromJson(json);

  factory LeaderboardEntry.fromSupabase(Map<String, dynamic> row) {
    return LeaderboardEntry(
      uid: row['auth_uid'] as String,
      displayName: row['display_name'] as String? ?? 'Player',
      elo: row['elo'] as int? ?? 1000,
      wins: row['wins'] as int? ?? 0,
      tier: row['tier'] as String? ?? 'bronze',
    );
  }
}
