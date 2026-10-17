import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/player_model.dart';

part 'leaderboard_service.g.dart';

@riverpod
LeaderboardService leaderboardService(Ref ref) =>
    LeaderboardService(Supabase.instance.client);

// ─────────────────────────────────────────────────────────────────────────────
// LeaderboardService
//
// Supabase replaces the Firestore denormalised /leaderboards collection.
// We query puk_huk_players directly — Postgres handles ORDER BY elo DESC
// efficiently with a B-tree index, so no separate leaderboard table is needed.
// ─────────────────────────────────────────────────────────────────────────────
class LeaderboardService {
  final SupabaseClient _supabase;

  LeaderboardService(this._supabase);

  /// Real-time global top-N leaderboard, ordered by ELO descending.
  /// Supabase .stream() automatically subscribes via Realtime.
  Future<List<LeaderboardEntry>> getGlobalTop({int limit = 100}) async {
    final rows = await _supabase
        .schema('pukhuk')
        .from('players')
        .select()
        .order('elo', ascending: false)
        .limit(limit);

    final entries = (rows as List)
        .cast<Map<String, dynamic>>()
        .map(LeaderboardEntry.fromSupabase)
        .toList();

    for (var i = 0; i < entries.length; i++) {
      entries[i] = entries[i].copyWith(rank: i + 1);
    }
    return entries;
  }

  /// "Local" leaderboard — players within ±[range] ELO of the current player.
  Stream<List<LeaderboardEntry>> watchNearbyRank(
    int myElo, {
    int range = 100,
    int limit = 20,
  }) {
    // .stream() doesn't support range filters; fetch with standard query
    // and re-emit via StreamController on initial + realtime changes.
    final controller =
        StreamController<List<LeaderboardEntry>>.broadcast();

    Future<void> fetch() async {
      try {
        final rows = await _supabase
            .schema('pukhuk')
            .from('players')
            .select()
            .gte('elo', myElo - range)
            .lte('elo', myElo + range)
            .order('elo', ascending: false)
            .limit(limit);
        if (!controller.isClosed) {
          controller.add(
            (rows as List)
                .cast<Map<String, dynamic>>()
                .map(LeaderboardEntry.fromSupabase)
                .toList(),
          );
        }
      } catch (_) {}
    }

    fetch();

    // Re-fetch when any puk_huk_players row is updated (ELO changes etc.)
    final channel = _supabase
        .channel('leaderboard_nearby_$myElo')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'puk_huk_players',
          callback: (_) => fetch(),
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
      controller.close();
    };

    return controller.stream;
  }

  /// One-time rank lookup — counts players with higher ELO + 1.
  Future<int?> getPlayerRank(String authUid) async {
    final playerRows = await _supabase
        .schema('pukhuk')
        .from('players')
        .select('elo')
        .eq('auth_uid', authUid)
        .limit(1);

    if ((playerRows as List).isEmpty) return null;
    final myElo = (playerRows.first as Map<String, dynamic>)['elo'] as int;

    // Count players strictly above this ELO
    final higherRows = await _supabase
        .schema('pukhuk')
        .from('players')
        .select('id')
        .gt('elo', myElo);

    return (higherRows as List).length + 1;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider wrappers for direct widget consumption
// ─────────────────────────────────────────────────────────────────────────────
@Riverpod(keepAlive: true)
Future<List<LeaderboardEntry>> globalLeaderboard(Ref ref) async {
  return ref.read(leaderboardServiceProvider).getGlobalTop();
}
