import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/player_model.dart';

part 'player_repository.g.dart';

@riverpod
PlayerRepository playerRepository(Ref ref) =>
    PlayerRepository(Supabase.instance.client);

// ─────────────────────────────────────────────────────────────────────────────
// PlayerRepository — Supabase data access
//
// Hub profile:  Supabase `profiles` table        (display_name, auth_user_id)
// Game profile: Supabase `puk_huk_players` table (ELO, stats, etc.)
//
// display_name is denormalised into puk_huk_players so stream queries stay
// on a single table (Supabase .stream() does not support JOINs).
// ─────────────────────────────────────────────────────────────────────────────
class PlayerRepository {
  final SupabaseClient _supabase;

  PlayerRepository(this._supabase);

  // ── Create both hub profile and game profile on sign-up ─────────────────
  Future<void> createPlayer({
    required String uid,
    required String displayName,
  }) async {
    // 1. Insert hub profile
    final profileResult = await _supabase
        .from('profiles')
        .insert({
          'auth_user_id': uid,
          'display_name': displayName,
        })
        .select('id')
        .single();

    final profileId = profileResult['id'] as String;

    // 2. Insert game profile (display_name denormalised for stream queries)
    await _supabase.schema('pukhuk').from('players').insert({
      'profile_id': profileId,
      'auth_uid': uid,
      'display_name': displayName,
    });
  }

  // ── Real-time stream of the current player's game profile ────────────────
  // Uses .stream() which subscribes via Supabase Realtime automatically.
  Stream<PlayerModel?> watchPlayer(String authUid) {
    return _supabase
        .schema('pukhuk')
        .from('players')
        .stream(primaryKey: ['id'])
        .eq('auth_uid', authUid)
        .map((rows) {
          if (rows.isEmpty) return null;
          return PlayerModel.fromSupabase(rows.first);
        });
  }

  // ── One-shot fetch ───────────────────────────────────────────────────────
  Future<PlayerModel?> getPlayer(String authUid) async {
    final rows = await _supabase
        .schema('pukhuk')
        .from('players')
        .select()
        .eq('auth_uid', authUid)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return PlayerModel.fromSupabase(rows.first as Map<String, dynamic>);
  }

  // ── Update arbitrary fields on the game profile ──────────────────────────
  Future<void> updatePlayer(
    String authUid,
    Map<String, dynamic> updates,
  ) =>
      _supabase
          .schema('pukhuk')
          .from('players')
          .update({...updates, 'updated_at': DateTime.now().toIso8601String()})
          .eq('auth_uid', authUid);

  // ── Update personal bests via server-side RPC (uses greatest()) ──────────
  Future<void> maybeUpdatePersonalBests({
    required String authUid,
    required double speedThisGame,
    required double distanceThisGame,
  }) =>
      _supabase.rpc('update_personal_bests', params: {
        'p_auth_uid': authUid,
        'p_speed': speedThisGame,
        'p_distance': distanceThisGame,
      });

  // ── Match history for profile screen — most recent first ─────────────────
  // Supabase .stream() doesn't support OR filters, so we use a StreamController
  // that re-fetches on a Postgres Changes subscription.
  Stream<List<Map<String, dynamic>>> watchMatchHistory(
    String authUid, {
    int limit = 20,
  }) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> fetch() async {
      try {
        final rows = await _supabase
            .schema('pukhuk')
            .from('matches')
            .select()
            .or('player1_id.eq.$authUid,player2_id.eq.$authUid')
            .order('scheduled_at', ascending: false)
            .limit(limit);
        if (!controller.isClosed) {
          controller.add((rows as List).cast<Map<String, dynamic>>());
        }
      } catch (_) {}
    }

    // Initial fetch
    fetch();

    // Re-fetch on any match record change involving this player
    final channel = _supabase
        .channel('match_history_$authUid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'puk_huk_matches',
          callback: (_) => fetch(),
        )
        .subscribe();

    controller.onCancel = () {
      channel.unsubscribe();
      controller.close();
    };

    return controller.stream;
  }

  // ── Online presence ──────────────────────────────────────────────────────
  Future<void> setOnlineStatus(String authUid, {required bool online}) =>
      _supabase.schema('pukhuk').from('players').update({
        'is_online': online,
        'last_seen': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('auth_uid', authUid);
}
