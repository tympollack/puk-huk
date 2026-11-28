import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sso_cookie.dart';

/// Session tokens extracted from a shared `.sunshade.icu` cookie or Hub SSO callback URL.
class ExtractedSsoTokens {
  final String accessToken;
  final String? refreshToken;
  final String? userId;

  const ExtractedSsoTokens({
    required this.accessToken,
    this.refreshToken,
    this.userId,
  });
}

/// Pure helpers for SunShade Hub SSO routing, cookie parsing, and token hydration.
abstract final class SsoAuthHelper {
  static String? projectRefFromUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final host = Uri.tryParse(url.trim())?.host ?? '';
    final ref = host.split('.').first;
    return ref.isEmpty ? null : ref;
  }

  /// Generates a cryptographically random anti-CSRF state token for Hub SSO redirects.
  static String generateSsoState() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Resolves the SunShade Hub login URL (`hub-stag` for staging/previews/localhost,
  /// `hub` for production) with `redirectTo` pointing back to the app origin.
  static Uri hubLoginUriFor(
    Uri currentUri, {
    String? fallbackOrigin,
    String? ssoState,
  }) {
    final host = currentUri.host.toLowerCase();
    final isStaging = host.contains('-stag') ||
        host.contains('staging') ||
        host.endsWith('.vercel.app') ||
        host == 'localhost' ||
        host == '127.0.0.1';

    final hubBase = isStaging
        ? 'https://hub-stag.sunshade.icu'
        : 'https://hub.sunshade.icu';

    final origin = (currentUri.hasScheme && currentUri.host.isNotEmpty)
        ? currentUri.origin
        : (fallbackOrigin ?? 'https://pukhuk.sunshade.icu');

    final redirectTarget = (ssoState != null && ssoState.isNotEmpty)
        ? Uri.parse(origin).replace(queryParameters: {'sso_state': ssoState}).toString()
        : origin;

    return Uri.parse('$hubBase/login').replace(
      queryParameters: {'redirectTo': redirectTarget},
    );
  }

  /// Checks whether [referrer] comes from a trusted SunShade Hub origin.
  static bool isTrustedHubReferrer(String? referrer) {
    if (referrer == null || referrer.trim().isEmpty) return false;
    final parsed = Uri.tryParse(referrer.trim());
    if (parsed == null) return false;
    final host = parsed.host.toLowerCase();
    if (parsed.scheme == 'https') {
      return host == 'hub.sunshade.icu' ||
          host == 'hub-stag.sunshade.icu' ||
          host == 'sunshade.icu' ||
          host.endsWith('-sunshade-systems.vercel.app');
    }
    if (parsed.scheme == 'http') {
      return host == 'localhost' || host == '127.0.0.1';
    }
    return false;
  }

  /// Extracts the `sso_state` nonce from query parameters or from `next` inside a hash callback.
  static String? extractSsoStateFromUri(Uri uri) {
    final direct = uri.queryParameters['sso_state'];
    if (direct != null && direct.isNotEmpty) return direct;

    final nextRaw = uri.queryParameters['next'];
    if (nextRaw != null && nextRaw.isNotEmpty) {
      final parsedNext = Uri.tryParse(nextRaw);
      final nextState = parsedNext?.queryParameters['sso_state'];
      if (nextState != null && nextState.isNotEmpty) return nextState;
    }

    if (uri.hasFragment && uri.fragment.isNotEmpty) {
      final fragment = uri.fragment;
      final queryPart = fragment.contains('?')
          ? fragment.split('?').last
          : (fragment.startsWith('/') ? '' : fragment);
      if (queryPart.contains('=')) {
        try {
          final fragmentParams = Uri.splitQueryString(queryPart);
          final fragState = fragmentParams['sso_state'];
          if (fragState != null && fragState.isNotEmpty) return fragState;

          final fragNext = fragmentParams['next'];
          if (fragNext != null && fragNext.isNotEmpty) {
            final parsedNext = Uri.tryParse(fragNext);
            final nextState = parsedNext?.queryParameters['sso_state'];
            if (nextState != null && nextState.isNotEmpty) return nextState;
          }
        } catch (_) {}
      }
    }

    return null;
  }

  /// Strips SSO callback tokens and transient handshake params from [uri] without
  /// retaining null-replaced fragments (Dart's `Uri.replace` preserves existing fragments on null).
  static Uri stripAuthTokensFromUri(Uri uri) {
    final query = Map<String, String>.from(uri.queryParameters)
      ..remove('access_token')
      ..remove('refresh_token')
      ..remove('hub_jwt')
      ..remove('token')
      ..remove('user_id')
      ..remove('next')
      ..remove('sso_state');

    var fragment = uri.fragment;
    if (fragment.contains('access_token=') ||
        fragment.contains('refresh_token=') ||
        fragment.contains('hub_jwt=') ||
        fragment.contains('token=')) {
      if (fragment.startsWith('/')) {
        fragment = fragment.split('?').first;
      } else {
        fragment = '';
      }
    }

    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      queryParameters: query.isEmpty ? null : query,
      fragment: fragment.isEmpty ? null : fragment,
    );
  }

  /// Extracts `access_token` and `refresh_token` from query parameters or URL fragment.
  static ExtractedSsoTokens? extractTokensFromUri(Uri uri) {
    String? accessToken = uri.queryParameters['access_token'] ??
        uri.queryParameters['hub_jwt'] ??
        uri.queryParameters['token'];
    String? refreshToken = uri.queryParameters['refresh_token'];
    String? userId = uri.queryParameters['user_id'];

    if (uri.hasFragment && uri.fragment.isNotEmpty) {
      final fragment = uri.fragment;
      // Support both `access_token=...&refresh_token=...` and `/auth/callback?access_token=...`
      final queryPart = fragment.contains('?')
          ? fragment.split('?').last
          : (fragment.startsWith('/') ? '' : fragment);
      if (queryPart.contains('=')) {
        try {
          final fragmentParams = Uri.splitQueryString(queryPart);
          accessToken ??= fragmentParams['access_token'] ??
              fragmentParams['hub_jwt'] ??
              fragmentParams['token'];
          refreshToken ??= fragmentParams['refresh_token'];
          userId ??= fragmentParams['user_id'];
        } catch (_) {}
      }
    }

    if (accessToken == null || accessToken.trim().isEmpty) {
      return null;
    }

    return ExtractedSsoTokens(
      accessToken: accessToken.trim(),
      refreshToken: refreshToken?.trim(),
      userId: userId?.trim() ?? tryDecodeJwtSub(accessToken.trim()),
    );
  }

  /// Parses Supabase session tokens from `document.cookie` (`sb-<ref>-auth-token`
  /// standalone or chunked `.0`/`.1`, JSON or `base64-` encoded).
  static ExtractedSsoTokens? parseCookieSession(
    String cookieHeader, {
    String? projectRef,
  }) {
    if (cookieHeader.trim().isEmpty) return null;

    final cookies = <String, String>{};
    for (final pair in cookieHeader.split(';')) {
      final eqIdx = pair.indexOf('=');
      if (eqIdx <= 0) continue;
      final key = pair.substring(0, eqIdx).trim();
      final rawVal = pair.substring(eqIdx + 1).trim();
      try {
        cookies[key] = Uri.decodeComponent(rawVal);
      } catch (_) {
        cookies[key] = rawVal;
      }
    }

    final projectCookie = RegExp(r'^sb-(.+)-auth-token(\.\d+)?$');
    final authKeys = cookies.keys.where((k) {
      if (!(k.contains('-auth-token') || k == 'sb-auth-token')) return false;
      if (projectRef == null || projectRef.isEmpty) return true;
      final match = projectCookie.firstMatch(k);
      return match == null || match.group(1) == projectRef;
    }).toList();

    if (authKeys.isNotEmpty) {
      final baseToChunks = <String, List<MapEntry<int, String>>>{};
      final standaloneKeys = <String>[];

      for (final key in authKeys) {
        final dotIndex = key.lastIndexOf('.');
        if (dotIndex != -1) {
          final chunkNum = int.tryParse(key.substring(dotIndex + 1));
          if (chunkNum != null) {
            final base = key.substring(0, dotIndex);
            baseToChunks
                .putIfAbsent(base, () => [])
                .add(MapEntry(chunkNum, cookies[key]!));
            continue;
          }
        }
        standaloneKeys.add(key);
      }

      for (final chunks in baseToChunks.values) {
        chunks.sort((a, b) => a.key.compareTo(b.key));
        final combined = chunks.map((c) => c.value).join();
        final session = _decodeTokenPayload(combined);
        if (session != null) return session;
      }

      for (final key in standaloneKeys) {
        final session = _decodeTokenPayload(cookies[key]!);
        if (session != null) return session;
      }
    }

    final directToken = cookies['sb-access-token'] ??
        cookies['access_token'] ??
        cookies['sunshade_session'] ??
        cookies['hub_jwt'];
    if (directToken != null && directToken.isNotEmpty) {
      return ExtractedSsoTokens(
        accessToken: directToken,
        refreshToken: cookies['sb-refresh-token'] ?? cookies['refresh_token'],
        userId: cookies['user_id'] ?? tryDecodeJwtSub(directToken),
      );
    }

    return null;
  }

  static ExtractedSsoTokens? _decodeTokenPayload(String raw) {
    var payload = raw.trim();
    if (payload.startsWith('base64-')) {
      try {
        final b64 = payload.substring(7);
        payload = utf8.decode(base64Url.decode(base64Url.normalize(b64)));
      } catch (_) {
        return null;
      }
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is List && decoded.isNotEmpty) {
        final accessToken = decoded[0]?.toString();
        final refreshToken = decoded.length > 1 ? decoded[1]?.toString() : null;
        if (accessToken != null && accessToken.isNotEmpty) {
          return ExtractedSsoTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: tryDecodeJwtSub(accessToken),
          );
        }
      } else if (decoded is Map<String, dynamic>) {
        final sessionMap = decoded['currentSession'] is Map<String, dynamic>
            ? decoded['currentSession'] as Map<String, dynamic>
            : decoded;
        final accessToken = sessionMap['access_token']?.toString();
        final refreshToken = sessionMap['refresh_token']?.toString();
        final userId = sessionMap['user'] is Map<String, dynamic>
            ? (sessionMap['user'] as Map<String, dynamic>)['id']?.toString()
            : (sessionMap['user_id']?.toString() ??
                (accessToken != null ? tryDecodeJwtSub(accessToken) : null));
        if (accessToken != null && accessToken.isNotEmpty) {
          return ExtractedSsoTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
          );
        }
      }
    } catch (_) {
      if (payload.split('.').length == 3) {
        return ExtractedSsoTokens(
          accessToken: payload,
          userId: tryDecodeJwtSub(payload),
        );
      }
    }
    return null;
  }

  static String? tryDecodeJwtSub(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      final jsonStr =
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic> && decoded['sub'] is String) {
        return decoded['sub'] as String;
      }
    } catch (_) {}
    return null;
  }

  static bool isJwtUnexpired(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return false;
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = decoded is Map<String, dynamic> ? decoded['exp'] : null;
      if (exp is! num) return false;
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
      return expiry
          .isAfter(DateTime.now().toUtc().add(const Duration(seconds: 30)));
    } catch (_) {
      return false;
    }
  }

  /// Hydrates Supabase Auth on startup from Hub SSO URL callback tokens or `.sunshade.icu` cookies.
  static Future<bool> hydrateOnStartup({
    required SupabaseClient client,
    required String supabaseUrl,
    Uri? currentUri,
  }) async {
    final uri = currentUri ?? Uri.base;
    final urlTokens = extractTokensFromUri(uri);
    if (urlTokens != null) {
      final callbackState = extractSsoStateFromUri(uri);
      final expectedState = consumeSsoLoginState();
      final hasMatchingState = expectedState != null &&
          expectedState.isNotEmpty &&
          callbackState == expectedState;
      final hasTrustedHubEntry = client.auth.currentSession == null &&
          isTrustedHubReferrer(readDocumentReferrer());

      clearUrlAuthTokens();

      if (hasMatchingState || hasTrustedHubEntry) {
        final ok = await _applyTokens(client, urlTokens);
        if (ok) return true;
      } else {
        debugPrint('[SsoAuthHelper] Rejected unsolicited URL callback tokens.');
      }
    }

    if (!kIsWeb) return client.auth.currentSession != null;

    if (client.auth.currentSession != null &&
        !client.auth.currentSession!.isExpired) {
      return true;
    }

    final projectRef = projectRefFromUrl(supabaseUrl);
    final cookieTokens = parseCookieSession(
      readBrowserCookies(),
      projectRef: projectRef,
    );
    if (cookieTokens == null) return false;

    return _applyTokens(client, cookieTokens);
  }

  static Future<bool> _applyTokens(
    SupabaseClient client,
    ExtractedSsoTokens tokens,
  ) async {
    if (tokens.refreshToken != null && tokens.refreshToken!.isNotEmpty) {
      try {
        final res = await client.auth.setSession(tokens.refreshToken!);
        if (res.session != null) return true;
      } on AuthException catch (e) {
        debugPrint('[SsoAuthHelper] setSession rejected (${e.statusCode}): ${e.message}');
      } catch (e) {
        debugPrint('[SsoAuthHelper] setSession failed: ${e.runtimeType}');
      }
    }

    if (!isJwtUnexpired(tokens.accessToken)) return false;

    try {
      // Verify access token signature & user identity with Supabase Auth before admitting session.
      final userRes = await client.auth.getUser(tokens.accessToken);
      final verifiedUser = userRes.user;
      if (verifiedUser == null) return false;

      final sessionJson = jsonEncode({
        'access_token': tokens.accessToken,
        'token_type': 'bearer',
        'user': verifiedUser.toJson(),
      });
      final res = await client.auth.recoverSession(sessionJson);
      return res.session != null;
    } catch (e) {
      debugPrint('[SsoAuthHelper] Access token verification/recovery failed: ${e.runtimeType}');
      return false;
    }
  }
}
