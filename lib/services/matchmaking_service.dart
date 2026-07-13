import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/models/player_model.dart';
import 'elo_service.dart';

part 'matchmaking_service.g.dart';

@riverpod
MatchmakingService matchmakingService(MatchmakingServiceRef ref) =>
    MatchmakingService(Supabase.instance.client);

// ─────────────────────────────────────────────────────────────────────────────
// State emitted by the matchmaking stream
// ─────────────────────────────────────────────────────────────────────────────
enum MatchmakingStatus { idle, searching, found, error, timeout }

class MatchmakingState {
  final MatchmakingStatus status;
  final String? matchId;
  final String? sessionId;
  final String? opponentId;
  final String? errorMessage;
  final Duration waitTime;
  final int currentEloTolerance;

  const MatchmakingState({
    this.status = MatchmakingStatus.idle,
    this.matchId,
    this.sessionId,
    this.opponentId,
    this.errorMessage,
    this.waitTime = Duration.zero,
    this.currentEloTolerance = 150,
  });

  MatchmakingState copyWith({
    MatchmakingStatus? status,
    String? matchId,
    String? sessionId,
    String? opponentId,
    String? errorMessage,
    Duration? waitTime,
    int? currentEloTolerance,
  }) =>
      MatchmakingState(
        status: status ?? this.status,
        matchId: matchId ?? this.matchId,
        sessionId: sessionId ?? this.sessionId,
        opponentId: opponentId ?? this.opponentId,
        errorMessage: errorMessage ?? this.errorMessage,
        waitTime: waitTime ?? this.waitTime,
        currentEloTolerance: currentEloTolerance ?? this.currentEloTolerance,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// MatchmakingService
//
// Flow:
//   1. Player upserts a row into puk_huk_matchmaking_queue
//   2. Periodic timer + Realtime INSERT subscription watch for opponents
//   3. ELO tolerance expands +50 every 15 s (max 500)
//   4. On match: puk_huk_attempt_pair() RPC acquires a Postgres FOR UPDATE
//      lock on the opponent row — prevents double-matching race conditions
//   5. Both players are emitted MatchmakingStatus.found with the sessionId
//
// The ELO string-literal bug from the original Firestore implementation is
// fixed by the puk_huk_resolve_match() RPC, which receives real UUIDs.
// ─────────────────────────────────────────────────────────────────────────────
class MatchmakingService {
  final SupabaseClient _supabase;

  RealtimeChannel? _queueChannel;
  Timer? _toleranceTimer;
  Timer? _waitTimer;
  Timer? _timeoutTimer;
  DateTime? _searchStart;

  static const _toleranceExpandInterval = Duration(seconds: 15);
  static const _toleranceStep = 50;
  static const _maxTolerance = 500;
  static const _searchTimeout = Duration(minutes: 3);

  MatchmakingService(this._supabase);

  // ─────────────────────────────────────────────────────────────────────────
  // Join queue — returns a stream of MatchmakingState updates
  // ─────────────────────────────────────────────────────────────────────────
  Stream<MatchmakingState> joinQueue(PlayerModel player) {
    final controller = StreamController<MatchmakingState>.broadcast();
    var tolerance = 150;
    _searchStart = DateTime.now();

    void emit(MatchmakingState s) {
      if (!controller.isClosed) controller.add(s);
    }

    // Inner closure captures tolerance by reference — updates as it expands.
    Future<void> checkCandidates() async {
      if (controller.isClosed) return;
      try {
        final rows = await _supabase
            .schema('pukhuk')
            .from('matchmaking_queue')
            .select()
            .eq('status', 'searching');

        final candidates = (rows as List)
            .cast<Map<String, dynamic>>()
            .where((r) => r['player_id'] as String != player.uid)
            .map(_CandidateEntry.fromRow)
            .where((c) => EloService.isWithinRange(
                  player.elo,
                  c.elo,
                  tolerance: tolerance,
                ))
            .toList()
          ..sort((a, b) =>
              EloService.matchCompatibility(player.elo, b.elo)
                  .compareTo(EloService.matchCompatibility(player.elo, a.elo)));

        if (candidates.isEmpty) return;

        await _attemptPair(
          player: player,
          opponent: candidates.first,
          emit: emit,
          controller: controller,
        );
      } catch (_) {
        // Ignore transient fetch errors during search
      }
    }

    // ── Initial state + queue entry ────────────────────────────────────────
    emit(const MatchmakingState(status: MatchmakingStatus.searching));

    _supabase.schema('pukhuk').from('matchmaking_queue').upsert({
      'player_id': player.uid,
      'elo': player.elo,
      'games_played': player.totalGames,
      'status': 'searching',
      'joined_at': DateTime.now().toIso8601String(),
    }).catchError((Object e) {
      emit(MatchmakingState(
        status: MatchmakingStatus.error,
        errorMessage: e.toString(),
      ));
    });

    // Initial candidate scan
    checkCandidates();

    // ── ELO tolerance expansion ────────────────────────────────────────────
    _toleranceTimer = Timer.periodic(_toleranceExpandInterval, (_) {
      tolerance = (tolerance + _toleranceStep).clamp(0, _maxTolerance);
      emit(MatchmakingState(
        status: MatchmakingStatus.searching,
        waitTime: DateTime.now().difference(_searchStart!),
        currentEloTolerance: tolerance,
      ));
      checkCandidates();
    });

    // ── Wait-time UI update (every 3 s) ────────────────────────────────────
    _waitTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      emit(MatchmakingState(
        status: MatchmakingStatus.searching,
        waitTime: DateTime.now().difference(_searchStart!),
        currentEloTolerance: tolerance,
      ));
      checkCandidates();
    });

    // ── 3-minute timeout ───────────────────────────────────────────────────
    _timeoutTimer = Timer(_searchTimeout, () async {
      await leaveQueue(player.uid);
      emit(const MatchmakingState(status: MatchmakingStatus.timeout));
      controller.close();
    });

    // ── Realtime INSERT listener — fires when a new player joins the queue ─
    _queueChannel = _supabase
        .channel('matchmaking_${player.uid}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'pukhuk',
          table: 'matchmaking_queue',
          callback: (_) => checkCandidates(),
        )
        .subscribe();

    controller.onCancel = () {
      _cancelTimers();
      _queueChannel?.unsubscribe();
      _queueChannel = null;
    };

    return controller.stream;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Atomic pairing via Postgres RPC — eliminates double-matching
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _attemptPair({
    required PlayerModel player,
    required _CandidateEntry opponent,
    required void Function(MatchmakingState) emit,
    required StreamController<MatchmakingState> controller,
  }) async {
    final matchId = const Uuid().v4();
    final sessionId = const Uuid().v4();

    try {
      final success = await _supabase.rpc('attempt_pair', params: {
        'p_my_id': player.uid,
        'p_opponent_id': opponent.playerId,
        'p_match_id': matchId,
        'p_session_id': sessionId,
        'p_my_elo': player.elo,
        'p_opponent_elo': opponent.elo,
      });

      if (success == true) {
        _cancelTimers();
        _queueChannel?.unsubscribe();
        _queueChannel = null;

        emit(MatchmakingState(
          status: MatchmakingStatus.found,
          matchId: matchId,
          sessionId: sessionId,
          opponentId: opponent.playerId,
          waitTime: DateTime.now().difference(_searchStart!),
        ));

        await controller.close();
      }
      // success == false → opponent was taken; keep searching
    } catch (_) {
      // Transient error — keep searching
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Leave queue (cancel search or called on dispose)
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> leaveQueue(String playerId) async {
    _cancelTimers();
    _queueChannel?.unsubscribe();
    _queueChannel = null;
    try {
      await _supabase
          .schema('pukhuk')
          .from('matchmaking_queue')
          .delete()
          .eq('player_id', playerId);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Resolve completed match — ELO update via puk_huk_resolve_match RPC
  // Fixes the original string-literal bug: player IDs are real UUIDs here.
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> resolveMatch({
    required String matchId,
    required String winnerId,
    required String loserId,
    required int winnerElo,
    required int loserElo,
    required int winnerGamesPlayed,
    required int loserGamesPlayed,
    required int winnerScore,
    required int loserScore,
  }) async {
    final result = EloService.calculateMatch(
      winnerElo: winnerElo,
      loserElo: loserElo,
      winnerGamesPlayed: winnerGamesPlayed,
      loserGamesPlayed: loserGamesPlayed,
    );

    await _supabase.rpc('resolve_match', params: {
      'p_match_id': matchId,
      'p_winner_id': winnerId,
      'p_loser_id': loserId,
      'p_winner_elo_change': result.winnerEloChange,
      'p_loser_elo_change': result.loserEloChange,
      'p_winner_new_elo': result.winnerNewElo,
      'p_loser_new_elo': result.loserNewElo,
      'p_winner_score': winnerScore,
      'p_loser_score': loserScore,
    });
  }

  void _cancelTimers() {
    _toleranceTimer?.cancel();
    _waitTimer?.cancel();
    _timeoutTimer?.cancel();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal queue candidate model
// ─────────────────────────────────────────────────────────────────────────────
class _CandidateEntry {
  final String playerId;
  final int elo;
  final int gamesPlayed;

  _CandidateEntry({
    required this.playerId,
    required this.elo,
    required this.gamesPlayed,
  });

  factory _CandidateEntry.fromRow(Map<String, dynamic> row) {
    return _CandidateEntry(
      playerId: row['player_id'] as String,
      elo: row['elo'] as int? ?? 1000,
      gamesPlayed: row['games_played'] as int? ?? 0,
    );
  }
}
