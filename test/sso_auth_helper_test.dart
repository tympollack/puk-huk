import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puk_huk/core/services/sso_auth_helper.dart';

String _makeJwt({required String sub, required int expSeconds}) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256', 'typ': 'JWT'})));
  final payload = base64Url.encode(utf8.encode(jsonEncode({'sub': sub, 'exp': expSeconds})));
  return '$header.$payload.sig';
}

void main() {
  group('SsoAuthHelper.hubLoginUriFor', () {
    test('routes staging hosts to hub-stag.sunshade.icu', () {
      final uri = SsoAuthHelper.hubLoginUriFor(
        Uri.parse('https://pukhuk-stag.sunshade.icu/#/lobby'),
      );
      expect(uri.host, equals('hub-stag.sunshade.icu'));
      expect(uri.path, equals('/login'));
      expect(uri.queryParameters['redirectTo'], equals('https://pukhuk-stag.sunshade.icu'));
    });

    test('routes vercel previews and localhost to hub-stag.sunshade.icu', () {
      final vercelUri = SsoAuthHelper.hubLoginUriFor(
        Uri.parse('https://pukhuk-abc-sunshade-systems.vercel.app/#/login'),
      );
      expect(vercelUri.host, equals('hub-stag.sunshade.icu'));
      expect(
        vercelUri.queryParameters['redirectTo'],
        equals('https://pukhuk-abc-sunshade-systems.vercel.app'),
      );

      final localUri = SsoAuthHelper.hubLoginUriFor(
        Uri.parse('http://localhost:8080/#/lobby'),
      );
      expect(localUri.host, equals('hub-stag.sunshade.icu'));
      expect(localUri.queryParameters['redirectTo'], equals('http://localhost:8080'));
    });

    test('routes production host to hub.sunshade.icu', () {
      final uri = SsoAuthHelper.hubLoginUriFor(
        Uri.parse('https://pukhuk.sunshade.icu/#/lobby'),
      );
      expect(uri.host, equals('hub.sunshade.icu'));
      expect(uri.path, equals('/login'));
      expect(uri.queryParameters['redirectTo'], equals('https://pukhuk.sunshade.icu'));
    });
  });

  group('SsoAuthHelper.extractTokensFromUri', () {
    test('extracts tokens from query parameters', () {
      final jwt = _makeJwt(sub: 'user-1', expSeconds: 9999999999);
      final tokens = SsoAuthHelper.extractTokensFromUri(
        Uri.parse('https://pukhuk.sunshade.icu/?access_token=$jwt&refresh_token=ref_123'),
      );
      expect(tokens, isNotNull);
      expect(tokens!.accessToken, equals(jwt));
      expect(tokens.refreshToken, equals('ref_123'));
      expect(tokens.userId, equals('user-1'));
    });

    test('extracts tokens from hash fragment callbacks', () {
      final jwt = _makeJwt(sub: 'user-2', expSeconds: 9999999999);
      final tokens = SsoAuthHelper.extractTokensFromUri(
        Uri.parse('https://pukhuk.vercel.app/auth/callback#access_token=$jwt&refresh_token=ref_456'),
      );
      expect(tokens, isNotNull);
      expect(tokens!.accessToken, equals(jwt));
      expect(tokens.refreshToken, equals('ref_456'));
      expect(tokens.userId, equals('user-2'));
    });

    test('ignores go_router hash path fragments without tokens', () {
      final tokens = SsoAuthHelper.extractTokensFromUri(
        Uri.parse('https://pukhuk.sunshade.icu/#/lobby'),
      );
      expect(tokens, isNull);
    });
  });

  group('SsoAuthHelper.parseCookieSession', () {
    test('parses base64 chunked sb-<ref>-auth-token cookies and filters other refs', () {
      final jwt = _makeJwt(sub: 'user-3', expSeconds: 9999999999);
      final jsonStr = jsonEncode({
        'access_token': jwt,
        'refresh_token': 'ref_chunk',
        'user': {'id': 'user-3'},
      });
      final encoded = 'base64-${base64Url.encode(utf8.encode(jsonStr))}';
      final mid = encoded.length ~/ 2;
      final c0 = Uri.encodeComponent(encoded.substring(0, mid));
      final c1 = Uri.encodeComponent(encoded.substring(mid));

      final otherPayload = Uri.encodeComponent(jsonEncode({
        'access_token': 'wrong',
        'refresh_token': 'wrong_ref',
      }));

      final cookieHeader =
          'sb-otherproj-auth-token=$otherPayload; sb-tpbpmhscsxchnezukpev-auth-token.0=$c0; sb-tpbpmhscsxchnezukpev-auth-token.1=$c1';

      final session = SsoAuthHelper.parseCookieSession(
        cookieHeader,
        projectRef: 'tpbpmhscsxchnezukpev',
      );
      expect(session, isNotNull);
      expect(session!.accessToken, equals(jwt));
      expect(session.refreshToken, equals('ref_chunk'));
      expect(session.userId, equals('user-3'));
    });
  });
}
