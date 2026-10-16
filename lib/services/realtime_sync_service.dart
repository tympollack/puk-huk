import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/game_session_model.dart';

part 'realtime_sync_service.g.dart';

@riverpod
RealtimeSyncService realtimeSyncService(Ref ref) =>
    RealtimeSyncService(Supabase.instance.client);

class RealtimeSyncService {
  final SupabaseClient _supabase;
  final Map<String, RealtimeChannel> _channels = {};
  final Map<String, StreamController<GameSessionState>> _sessionControllers = {};
  final Map<String, StreamController<Map<String, dynamic>>> _presenceControllers = {};

  RealtimeSyncService(this._supabase);

  RealtimeChannel _channel(String sessionId) {
    return _channels.putIfAbsent(
      sessionId,
      () => _supabase.channel(
        'game_$sessionId',
        opts: const RealtimeChannelConfig(ack: true),
      ),
    );
  }

  Future<void> _ensureSubscribed(String sessionId) async {
    final ch = _channel(sessionId);
    ch.subscribe();
  }

  Stream<GameSessionState> watchSession(String sessionId) {
    if (_sessionControllers.containsKey(sessionId)) {
      return _sessionControllers[sessionId]!.stream;
    }

    final controller = StreamController<GameSessionState>.broadcast();
    _sessionControllers[sessionId] = controller;

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
    final channel = _channel(sessionId);
    channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'pukhuk',
        table: 'game_sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
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
      ).onPresenceSync((payload) {
        if (!_presenceControllers.containsKey(sessionId)) return;
        final presenceList = channel.presenceState();
        final presenceMap = <String, dynamic>{};
        
        for (final item in presenceList) {
          try {
            final dynamic pPayload = (item as dynamic).state;
            final playerId = pPayload['player_id'];
            if (playerId != null) {
              presenceMap[playerId] = pPayload;
            }
          } catch (_) {}
        }
        _presenceControllers[sessionId]?.add(presenceMap);
      });

    _ensureSubscribed(sessionId);

    controller.onCancel = () async {
      _sessionControllers.remove(sessionId);
      _presenceControllers.remove(sessionId);
      if (_channels[sessionId] == channel) {
        _channels.remove(sessionId);
      }
      await channel.unsubscribe();
      if (!controller.isClosed) {
        controller.close();
      }
    };

    return controller.stream;
  }

  Stream<Map<String, dynamic>> watchPresence(String sessionId) {
    if (_presenceControllers.containsKey(sessionId)) {
      return _presenceControllers[sessionId]!.stream;
    }
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    _presenceControllers[sessionId] = controller;
    
    // Emit initial presence if channel exists
    if (_channels.containsKey(sessionId)) {
      final presenceList = _channels[sessionId]!.presenceState();
      final presenceMap = <String, dynamic>{};
      
      for (final item in presenceList) {
        try {
          final dynamic pPayload = (item as dynamic).state;
          final playerId = pPayload['player_id'];
          if (playerId != null) {
            presenceMap[playerId] = pPayload;
          }
        } catch (_) {}
      }
      controller.add(presenceMap);
    }
    
    controller.onCancel = () {
      _presenceControllers.remove(sessionId);
      controller.close();
    };
    return controller.stream;
  }

  Future<void> trackPresence(String sessionId, String playerId) async {
    final ch = _channel(sessionId);
    await ch.track({
      'player_id': playerId,
      'online_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> submitTurn({
    required String matchId,
    required String playerId,
    required int expectedTurnNumber,
    required GameSessionState newState,
  }) async {
    try {
      await _supabase.rpc(
        'submit_turn',
        params: {
          'p_match_id': matchId,
          'p_player_id': playerId,
          'p_expected_turn_number': expectedTurnNumber,
          'p_new_state': newState.toJson(),
        },
      );
    } catch (e) {
      print('RPC submit_turn failed: $e');
      throw Exception('Failed to submit turn: $e');
    }
    
    // Optimistic local update
    _sessionControllers[matchId]?.add(newState);
  }
}
