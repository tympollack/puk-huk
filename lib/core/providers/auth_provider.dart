import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/player_model.dart';
import '../../services/player_repository.dart';
import '../services/sso_auth_helper.dart';
import '../services/sso_cookie.dart';
import '../supabase_config.dart';

part 'auth_provider.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Raw Supabase auth state — drives the go_router redirect guard.
// Emits the auth UID (String) when signed in, null when signed out.
// ─────────────────────────────────────────────────────────────────────────────
@Riverpod(keepAlive: true)
Stream<String?> authState(Ref ref) async* {
  final auth = Supabase.instance.client.auth;
  yield auth.currentSession?.user.id;
  yield* auth.onAuthStateChange.map((event) => event.session?.user.id);
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

@riverpod
Stream<PlayerModel?> playerById(Ref ref, String uid) {
  if (uid == 'bot_pukhuk' || uid == '00000000-0000-0000-0000-000000000000') {
    return Stream.value(PlayerModel(
      uid: uid,
      displayName: 'PUK_HUK_BOT',
      elo: 1500,
      totalGames: 0,
      wins: 0,
    ));
  }
  return ref.watch(playerRepositoryProvider).watchPlayer(uid).asStream();
}

// ─────────────────────────────────────────────────────────────────────────────
// AuthService — SunShade Hub SSO, guest play, and sign out via Supabase Auth
// ─────────────────────────────────────────────────────────────────────────────
@riverpod
AuthService authService(Ref ref) =>
    AuthService(Supabase.instance.client, ref.watch(playerRepositoryProvider));

class AuthService {
  final SupabaseClient _supabase;
  final PlayerRepository _playerRepo;

  AuthService(this._supabase, this._playerRepo);

  /// Routes the user through SunShade Hub Central SSO (`hub[-stag].sunshade.icu/login`).
  Future<void> signInWithSunShadeHub() async {
    final targetUri = SsoAuthHelper.hubLoginUriFor(Uri.base);
    if (kIsWeb) {
      redirectToUrl(targetUri.toString());
      return;
    }
    if (!await launchUrl(targetUri, mode: LaunchMode.externalApplication)) {
      throw Exception('Unable to open SunShade Hub SSO');
    }
  }

  /// Signs in anonymously as a guest and ensures a `pukhuk.players` row exists.
  Future<void> signInAsGuest() async {
    final response = await _supabase.auth.signInAnonymously();
    final user = response.user;
    if (user == null) return;
    await _playerRepo.getPlayer(user.id);
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
    if (kIsWeb) {
      clearSsoAuthCookies(SsoAuthHelper.projectRefFromUrl(SupabaseConfig.url));
    }
  }
}
