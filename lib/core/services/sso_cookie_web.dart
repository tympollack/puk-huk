import 'package:web/web.dart' as web;

String readBrowserCookies() => web.document.cookie;

String getCurrentOrigin() => web.window.location.origin;

void redirectToUrl(String url) {
  web.window.location.href = url;
}

void openExternalUrl(String url) {
  web.window.open(url, '_blank');
}

void clearUrlAuthTokens() {
  try {
    final currentUri = Uri.parse(web.window.location.href);
    final query = Map<String, String>.from(currentUri.queryParameters)
      ..remove('access_token')
      ..remove('refresh_token')
      ..remove('next');

    var fragment = currentUri.fragment;
    if (fragment.contains('access_token=') || fragment.contains('refresh_token=')) {
      if (fragment.startsWith('/')) {
        fragment = fragment.split('?').first;
      } else {
        fragment = '';
      }
    }

    final cleanUri = currentUri.replace(
      queryParameters: query.isEmpty ? null : query,
      fragment: fragment.isEmpty ? null : fragment,
    );
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
