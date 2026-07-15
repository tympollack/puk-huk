import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/player_model.dart';
import '../../services/player_repository.dart';

part 'auth_provider.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Raw Supabase auth state — drives the go_router redirect guard.
// Emits the auth UID (String) when signed in, null when signed out.
// ─────────────────────────────────────────────────────────────────────────────
@Riverpod(keepAlive: true)
Stream<String?> authState(Ref ref) {
  return Supabase.instance.client.auth.onAuthStateChange
      .map((event) => event.session?.user.id);
}

// ─────────────────────────────────────────────────────────────────────────────
// Current authenticated player — composite of hub profile + game profile.
// Null when not signed in or profile not yet created.
// ─────────────────────────────────────────────────────────────────────────────
@Riverpod(keepAlive: true)
Future<PlayerModel?> currentPlayer(Ref ref) async {
  final authValue = ref.watch(authStateProvider).value;
  if (authValue == null) {
    return null;
  }
  
  // Ensure the player profile exists (will auto-create if missing) before fetching
  await ref.read(playerRepositoryProvider).getPlayer(authValue);
  
  return ref.read(playerRepositoryProvider).watchPlayer(authValue);
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthService — sign in / sign up / sign out via Supabase Auth
// ─────────────────────────────────────────────────────────────────────────────
@riverpod
AuthService authService(Ref ref) =>
    AuthService(Supabase.instance.client, ref.watch(playerRepositoryProvider));

class AuthService {
  final SupabaseClient _supabase;
  final PlayerRepository _playerRepo;

  AuthService(this._supabase, this._playerRepo);

  Future<void> signInWithEmail(String email, String password) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'display_name': displayName},
    );

    final user = response.user;
    if (user == null) return;

    // Bootstrap hub profile + game profile.
    // PlayerRepository.createPlayer handles both inserts atomically.
    await _playerRepo.createPlayer(
      uid: user.id,
      displayName: displayName,
    );
  }

  Future<void> signOut() => _supabase.auth.signOut();
}
