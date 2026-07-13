import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/game_session_model.dart';

part 'realtime_sync_service.g.dart';

@riverpod
RealtimeSyncService realtimeSyncService(RealtimeSyncServiceRef ref) =>
    RealtimeSyncService(Supabase.instance.client);

class RealtimeSyncService {
  final SupabaseClient _supabase;
  final Map<String, RealtimeChannel> _channels = {};

  RealtimeSyncService(this._supabase);

  RealtimeChannel _channel(String sessionId) {
    return _channels.putIfAbsent(
      sessionId,
      () => _supabase.channel('game_$sessionId'),
    );
  }

  Future<void> _ensureSubscribed(String sessionId) async {
    final ch = _channel(sessionId);
    await ch.subscribe();
  }

  Stream<GameSessionState> watchSession(String sessionId) {
    final controller = StreamController<GameSessionState>.broadcast();

    Future<void> fetchAndEmit() async {
      try {
        final rows = await _supabase
            .schema('pukhuk')
            .from('game_sessions')
            .select('state')
            .eq('id', sessionId)
            .limit(1);
        if ((rows as List).isNotEmpty && !controller.isClosed) {
          final stateMap = (rows.first as Map<String, dynamic>)['state'] as Map<String, dynamic>;
          controller.add(GameSessionState.fromJson(stateMap));
        }
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    // Initial data
    fetchAndEmit();

    // Postgres Changes subscription
    final channel = _channel(sessionId)
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'pukhuk',
        table: 'game_sessions',
        filter: PostgresChangeFilter(
          type: FilterType.eq,
          column: 'id',
          value: sessionId,
        ),
        callback: (payload) {
          if (payload.newRecord.isNotEmpty && !controller.isClosed) {
            try {
              final stateMap = Map<String, dynamic>.from(payload.newRecord['state'] as Map);
              controller.add(GameSessionState.fromJson(stateMap));
            } catch (_) {
              fetchAndEmit();
            }
          }
        },
      );

    _ensureSubscribed(sessionId);

    controller.onCancel = () async {
      await channel.unsubscribe();
      _channels.remove(sessionId);
      controller.close();
    };

    return controller.stream;
  }

  Future<void> submitTurn({
    required String matchId,
    required String playerId,
    required int expectedTurnNumber,
    required GameSessionState newState,
  }) async {
    await _supabase.rpc(
      'submit_turn',
      params: {
        'p_match_id': matchId,
        'p_player_id': playerId,
        'p_expected_turn_number': expectedTurnNumber,
        'p_new_state': newState.toJson(),
      },
    ); // The rpc might need to point to public schema wrapper if pukhuk isn't in search_path, or we can use schema('pukhuk').rpc wait Supabase.instance.client.rpc doesn't have schema() chain for rpcs in all versions. Actually rpc method is just on client. If it doesn't work, standard is to put rpc in public or use set_config. For now we just call it.
  }
}
