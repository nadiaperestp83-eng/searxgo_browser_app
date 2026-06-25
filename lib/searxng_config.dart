class SearxNGConfig {
  static const String baseUrl =
      'https://searxng-railway-production-9bcc.up.railway.app';

  static String searchUrl(String query) =>
      '$baseUrl/search?q=${Uri.encodeQueryComponent(query)}&format=json';

  static const String homeUrl = baseUrl;
  static const String appName = 'SearxGo';
  static const int primaryColor = 0xFF1A1A2E;
  static const int accentColor = 0xFF00D4FF;

  static const List<String> trackerDomains = [
    'google-analytics.com',
    'googletagmanager.com',
    'doubleclick.net',
    'facebook.com/tr',
    'connect.facebook.net',
    'hotjar.com',
    'segment.com',
    'mixpanel.com',
    'amplitude.com',
    'intercom.io',
    'crisp.chat',
    'ads.twitter.com',
    'analytics.tiktok.com',
  ];

  static bool isTracker(String url) =>
      trackerDomains.any((t) => url.toLowerCase().contains(t));

  static String resolveInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return homeUrl;
    final looksLikeUrl = !trimmed.contains(' ') &&
        (trimmed.contains('.') ||
            trimmed.startsWith('http://') ||
            trimmed.startsWith('https://'));
    if (looksLikeUrl) {
      return trimmed.startsWith('http') ? trimmed : 'https://$trimmed';
    }
    return searchUrl(trimmed);
  }
}
