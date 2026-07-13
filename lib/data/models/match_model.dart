import 'package:freezed_annotation/freezed_annotation.dart';

part 'match_model.freezed.dart';
part 'match_model.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MatchModel — persistent match record
// Supabase table: puk_huk_matches
// ─────────────────────────────────────────────────────────────────────────────
enum MatchStatus { scheduled, active, completed, cancelled }

@freezed
class MatchModel with _$MatchModel {
  const factory MatchModel({
    required String matchId,
    required String player1Id,   // auth UID
    required String player2Id,   // auth UID
    required int player1EloAtTime,
    required int player2EloAtTime,
    @Default(MatchStatus.scheduled) MatchStatus status,
    String? winnerId,            // auth UID
    String? sessionId,           // links to puk_huk_game_sessions

    // ── ELO deltas (populated on completion via puk_huk_resolve_match RPC) ──
    @Default(0) int player1EloChange,
    @Default(0) int player2EloChange,

    // ── Final scores ─────────────────────────────────────────────────────────
    @Default(0) int player1ScoreFinal,
    @Default(0) int player2ScoreFinal,

    // ── Timestamps ───────────────────────────────────────────────────────────
    DateTime? scheduledAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) = _MatchModel;

  factory MatchModel.fromJson(Map<String, dynamic> json) =>
      _$MatchModelFromJson(json);

  /// Build from a `puk_huk_matches` Supabase row.
  factory MatchModel.fromSupabase(Map<String, dynamic> row) {
    return MatchModel(
      matchId: row['id'] as String,
      player1Id: row['player1_id'] as String,
      player2Id: row['player2_id'] as String,
      player1EloAtTime: row['player1_elo_at_time'] as int? ?? 1000,
      player2EloAtTime: row['player2_elo_at_time'] as int? ?? 1000,
      status: MatchStatus.values.firstWhere(
        (s) => s.name == (row['status'] as String? ?? 'scheduled'),
        orElse: () => MatchStatus.scheduled,
      ),
      winnerId: row['winner_id'] as String?,
      sessionId: row['session_id'] as String?,
      player1EloChange: row['player1_elo_change'] as int? ?? 0,
      player2EloChange: row['player2_elo_change'] as int? ?? 0,
      player1ScoreFinal: row['player1_score_final'] as int? ?? 0,
      player2ScoreFinal: row['player2_score_final'] as int? ?? 0,
      scheduledAt: row['scheduled_at'] != null
          ? DateTime.tryParse(row['scheduled_at'] as String)
          : null,
      startedAt: row['started_at'] != null
          ? DateTime.tryParse(row['started_at'] as String)
          : null,
      completedAt: row['completed_at'] != null
          ? DateTime.tryParse(row['completed_at'] as String)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QueueEntry — matchmaking queue record
// Supabase table: puk_huk_matchmaking_queue
// ─────────────────────────────────────────────────────────────────────────────
@freezed
class QueueEntry with _$QueueEntry {
  const factory QueueEntry({
    required String playerId,  // auth UID
    required int elo,
    required int gamesPlayed,
    @Default('searching') String status, // searching | matched | timeout
    String? matchId,
    DateTime? joinedAt,
  }) = _QueueEntry;

  factory QueueEntry.fromJson(Map<String, dynamic> json) =>
      _$QueueEntryFromJson(json);

  factory QueueEntry.fromSupabase(Map<String, dynamic> row) {
    return QueueEntry(
      playerId: row['player_id'] as String,
      elo: row['elo'] as int? ?? 1000,
      gamesPlayed: row['games_played'] as int? ?? 0,
      status: row['status'] as String? ?? 'searching',
      matchId: row['match_id'] as String?,
      joinedAt: row['joined_at'] != null
          ? DateTime.tryParse(row['joined_at'] as String)
          : null,
    );
  }
}
