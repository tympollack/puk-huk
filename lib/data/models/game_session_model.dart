import 'package:freezed_annotation/freezed_annotation.dart';

part 'game_session_model.freezed.dart';
part 'game_session_model.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Deterministic physics state — synced via pukhuk.game_sessions
// Full State Replacement pattern for deterministic gameplay.
// ─────────────────────────────────────────────────────────────────────────────

@freezed
abstract class PuckStateModel with _$PuckStateModel {
  const factory PuckStateModel({
    @JsonKey(name: 'puck_id') required String puckId,
    @JsonKey(name: 'owner_id') required String ownerId,
    required double x,
    required double y,
    required String status, // 'active', 'scoring', 'knocked_off'
  }) = _PuckStateModel;

  factory PuckStateModel.fromJson(Map<String, dynamic> json) =>
      _$PuckStateModelFromJson(json);
}

@freezed
abstract class ActionModel with _$ActionModel {
  const factory ActionModel({
    @JsonKey(name: 'player_id') required String playerId,
    @JsonKey(name: 'vector_x') required double vectorX,
    @JsonKey(name: 'vector_y') required double vectorY,
    required double rotation,
    required double force,
    required DateTime timestamp,
  }) = _ActionModel;

  factory ActionModel.fromJson(Map<String, dynamic> json) =>
      _$ActionModelFromJson(json);
}

@freezed
abstract class GameSessionState with _$GameSessionState {
  const factory GameSessionState({
    required String status, // 'active', 'completed'
    @JsonKey(name: 'turn_number') required int turnNumber,
    @JsonKey(name: 'current_turn_player_id') required String currentTurnPlayerId,
    required Map<String, int> scores,
    @JsonKey(name: 'last_action') ActionModel? lastAction,
    @JsonKey(name: 'board_state') @Default([]) List<PuckStateModel> boardState,
  }) = _GameSessionState;

  factory GameSessionState.fromJson(Map<String, dynamic> json) =>
      _$GameSessionStateFromJson(json);
}
