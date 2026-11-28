String readBrowserCookies() => '';

String getCurrentOrigin() => '';

String readDocumentReferrer() => '';

void saveSsoLoginState(String state) {}

String? consumeSsoLoginState() => null;

void redirectToUrl(String url) {}

void openExternalUrl(String url) {}

void clearUrlAuthTokens() {}

void clearSsoAuthCookies(String? projectRef) {}
