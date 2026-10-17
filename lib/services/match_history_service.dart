import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/providers/auth_provider.dart';
import '../data/models/game_session_model.dart';
import 'player_repository.dart';
import '../data/models/player_model.dart';

part 'match_history_service.g.dart';

class MatchHistoryItem {
  final String sessionId;
  final GameSessionState state;
  final DateTime createdAt;
  final PlayerModel opponent;
  final bool isMyTurn;
  final bool isCompleted;

  MatchHistoryItem({
    required this.sessionId,
    required this.state,
    required this.createdAt,
    required this.opponent,
    required this.isMyTurn,
    required this.isCompleted,
  });
}

@riverpod
Future<List<MatchHistoryItem>> matchHistory(Ref ref) async {
  final user = ref.watch(currentPlayerProvider).value;
  if (user == null) return [];

  final supabase = Supabase.instance.client;

  // Watch session updates so retained lobby cards reflect current scores and turns
  final channel = supabase
      .channel('match_history_realtime_${user.uid}')
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'pukhuk',
        table: 'game_sessions',
        callback: (_) {
          ref.invalidateSelf();
        },
      )
      .subscribe();

  ref.onDispose(() {
    supabase.removeChannel(channel);
  });
  
  // Call the RPC to get sessions
  final List<dynamic> response = await supabase.rpc('get_user_match_history', params: {
    'p_user_id': user.uid,
  });

  if (response.isEmpty) return [];

  final playerRepo = ref.read(playerRepositoryProvider);
  final List<MatchHistoryItem> items = [];

  for (final row in response) {
    final sessionId = row['id'] as String;
    final stateJson = row['state'] as Map<String, dynamic>;
    final state = GameSessionState.fromJson(stateJson);
    final createdAt = DateTime.parse(row['created_at'] as String);

    final opponentId = state.scores.keys.firstWhere(
      (id) => id != user.uid,
      orElse: () => '',
    );

    PlayerModel? opponent;
    if (opponentId == '00000000-0000-0000-0000-000000000000') {
      opponent = PlayerModel(
        uid: opponentId,
        displayName: 'Shuffle Bot',
        elo: 1200,
      );
    } else if (opponentId.isNotEmpty) {
      opponent = await playerRepo.getPlayer(opponentId);
    }
    
    // Default placeholder if opponent not found
    opponent ??= PlayerModel(
      uid: opponentId,
      displayName: 'Unknown Player',
      elo: 1200,
    );

    items.add(MatchHistoryItem(
      sessionId: sessionId,
      state: state,
      createdAt: createdAt,
      opponent: opponent,
      isMyTurn: state.currentTurnPlayerId == user.uid,
      isCompleted: state.status == 'completed' || state.status == 'forfeited',
    ));
  }

  return items;
}
