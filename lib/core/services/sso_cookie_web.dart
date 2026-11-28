import 'package:web/web.dart' as web;

import 'sso_auth_helper.dart';

const String _ssoStateStorageKey = 'pukhuk_sso_state';

String readBrowserCookies() => web.document.cookie;

String getCurrentOrigin() => web.window.location.origin;

String readDocumentReferrer() => web.document.referrer;

void saveSsoLoginState(String state) {
  try {
    web.window.sessionStorage.setItem(_ssoStateStorageKey, state);
  } catch (_) {}
}

String? consumeSsoLoginState() {
  try {
    final value = web.window.sessionStorage.getItem(_ssoStateStorageKey);
    web.window.sessionStorage.removeItem(_ssoStateStorageKey);
    return value;
  } catch (_) {
    return null;
  }
}

void redirectToUrl(String url) {
  web.window.location.href = url;
}

void openExternalUrl(String url) {
  web.window.open(url, '_blank');
}

void clearUrlAuthTokens() {
  try {
    final currentUri = Uri.parse(web.window.location.href);
    final cleanUri = SsoAuthHelper.stripAuthTokensFromUri(currentUri);
    web.window.history.replaceState(null, '', cleanUri.toString());
  } catch (_) {}
}

void clearSsoAuthCookies(String? projectRef) {
  try {
    final host = web.window.location.hostname.toLowerCase();
    final isSunShade = host == 'sunshade.icu' || host.endsWith('.sunshade.icu');
    final isHttps = web.window.location.protocol == 'https:';
    final prefix = (projectRef != null && projectRef.isNotEmpty)
        ? 'sb-$projectRef-auth-token'
        : 'sb-auth-token';

    final cookieNames = <String>[
      prefix,
      for (var i = 0; i < 10; i++) '$prefix.$i',
      'sb-access-token',
      'sb-refresh-token',
    ];

    for (final name in cookieNames) {
      final base = '$name=; Path=/; Max-Age=0; SameSite=Lax${isHttps ? '; Secure' : ''}';
      web.document.cookie = base;
      if (isSunShade) {
        web.document.cookie = '$base; domain=.sunshade.icu';
      }
    }
  } catch (_) {}
}
