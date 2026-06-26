import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'searxng_config.dart';
import 'models/search_result.dart';
import 'vpn_service.dart';
import 'dart:ui';

enum _Screen { home, results, webview }

class SearxGoBrowser extends StatefulWidget {
  const SearxGoBrowser({Key? key}) : super(key: key);

  @override
  State<SearxGoBrowser> createState() => _SearxGoBrowserState();
}

class _SearxGoBrowserState extends State<SearxGoBrowser> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  InAppWebViewController? _webController;

  _Screen _screen = _Screen.home;
  bool _isSearching = false;
  bool _isEditing = false;
  double _webProgress = 0;
  bool _webLoading = false;
  int _blockedCount = 0;
  bool _currentIsHttps = false;
  String _currentUrl = '';

  SearchResponse? _searchResponse;
  String? _errorMsg;

  static const Color _cardBg     = Color(0xFFFFFFFF);
  static const Color _cardBorder = Color(0xFFE0E0E0);
  static const Color _textMain   = Color(0xFF1A1A1A);
  static const Color _textSub    = Color(0xFF5F5F5F);
  static const Color _iconGray   = Color(0xFF5F5F5F);
  static const Color _accent     = Color(0xFF00D4FF);

  final InAppWebViewSettings _webSettings = InAppWebViewSettings(
    useShouldOverrideUrlLoading: true,
    useShouldInterceptRequest: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    allowFileAccess: true,
    allowContentAccess: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    incognito: true,
    cacheEnabled: false,
    clearCache: true,
    builtInZoomControls: false,
    displayZoomControls: false,
    supportZoom: true,
    userAgent:
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  );

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    _searchFocus.addListener(() {
      final hasFocus = _searchFocus.hasFocus;
      setState(() => _isEditing = hasFocus);
      if (_screen == _Screen.webview) {
        if (hasFocus) {
          _searchController.text = _currentUrl;
          _searchController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchController.text.length,
          );
        } else {
          _searchController.text = _domainOnly(_currentUrl);
        }
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String _domainOnly(String url) {
    if (url.isEmpty) return '';
    try {
      final uri = Uri.parse(url);
      if (uri.host.isEmpty) return url;
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  // ================================================================
  //  Script agressivo para remover cabeçalho e fundo opaco
  // ================================================================
  void _injectHideHeaderCss(InAppWebViewController controller) {
    const script = """
      (function() {
        function removeHeaders() {
          // Seletores genéricos
          const selectors = [
            'header', '.header', '#header', 'nav', '.nav', '#nav',
            '.navbar', '#navbar', '.top-bar', '#top-bar',
            '.searxng-header', '.header-container', '.header-wrapper',
            '[role="banner"]', '[class*="header"]', '[id*="header"]',
            '[class*="top"]', '[id*="top"]'
          ];
          selectors.forEach(sel => {
            document.querySelectorAll(sel).forEach(el => {
              const rect = el.getBoundingClientRect();
              if (rect.top < 150 && rect.height > 20) {
                el.remove();
              }
            });
          });
          // Remove elementos com texto "SearxNG" ou "Pesquisar" no topo
          document.querySelectorAll('*').forEach(el => {
            const text = el.textContent || '';
            if ((text.includes('SearxNG') || text.includes('Pesquisar')) && 
                el.getBoundingClientRect().top < 150) {
              el.remove();
            }
          });
          // Torna fundo transparente
          document.documentElement.style.background = 'transparent !important';
          document.body.style.background = 'transparent !important';
          document.body.style.margin = '0';
          document.body.style.padding = '0';
        }

        removeHeaders();

        const observer = new MutationObserver(() => {
          removeHeaders();
        });
        observer.observe(document.body, { childList: true, subtree: true });

        setTimeout(removeHeaders, 500);
        setTimeout(removeHeaders, 1000);
        setTimeout(removeHeaders, 2000);
        setTimeout(removeHeaders, 3000);
      })();
    """;
    controller.evaluateJavascript(source: script);
  }

  // ================================================================
  //  Carregar URL com tema simple
  // ================================================================
  void _loadInWebView(String url) {
    final uri = Uri.parse(url);
    final cleanUrl = uri
        .replace(queryParameters: {'theme': 'simple', ...uri.queryParameters})
        .toString();

    setState(() {
      _screen = _Screen.webview;
      _webProgress = 0;
      _webLoading = true;
      _currentIsHttps = cleanUrl.startsWith('https://');
      _currentUrl = cleanUrl;
    });
    _webController?.loadUrl(urlRequest: URLRequest(url: WebUri(cleanUrl)));
    _searchController.text = _domainOnly(cleanUrl);
  }

  void _onSubmit(String input) {
    final t = input.trim();
    if (t.isEmpty) return;
    _searchFocus.unfocus();
    if (SearxNGConfig.looksLikeUrl(t)) {
      _loadInWebView(SearxNGConfig.toUrl(t));
    } else {
      _doSearch(t);
    }
  }

  Future<void> _doSearch(String query) async {
    setState(() {
      _isSearching = true;
      _screen = _Screen.results;
      _errorMsg = null;
      _searchResponse = null;
      _searchController.text = query;
    });

    try {
      final uri = Uri.parse(SearxNGConfig.searchUrl(query));
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        'User-Agent': 'SearxGo/1.0',
      }).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final json = jsonDecode(utf8.decode(res.bodyBytes));
        setState(() {
          _searchResponse = SearchResponse.fromJson(json);
          _isSearching = false;
        });
      } else {
        setState(() {
          _errorMsg = 'Erro ${res.statusCode}';
          _isSearching = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg = 'Falha: $e';
        _isSearching = false;
      });
    }
  }

  void _goBack() {
    if (_screen == _Screen.webview) {
      if (_searchResponse != null) {
        setState(() {
          _screen = _Screen.results;
          _searchController.text = _searchResponse!.query;
          _currentIsHttps = false;
          _currentUrl = '';
        });
      } else {
        setState(() {
          _screen = _Screen.home;
          _searchController.clear();
          _currentIsHttps = false;
          _currentUrl = '';
        });
      }
    } else if (_screen == _Screen.results) {
      setState(() {
        _screen = _Screen.home;
        _searchController.clear();
      });
    }
  }

  Future<void> _burnAll() async {
    await CookieManager.instance().deleteAllCookies();
    await _webController?.clearCache();
    await _webController?.clearHistory();
    await _webController?.evaluateJavascript(source: '''
      try { localStorage.clear(); } catch(e) {}
      try { sessionStorage.clear(); } catch(e) {}
      try {
        indexedDB.databases().then(function(dbs) {
          dbs.forEach(function(db) { indexedDB.deleteDatabase(db.name); });
        });
      } catch(e) {}
    ''');
    await _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
    if (mounted) {
      setState(() {
        _screen = _Screen.home;
        _searchController.clear();
        _searchResponse = null;
        _errorMsg = null;
        _blockedCount = 0;
        _webProgress = 0;
        _webLoading = false;
        _currentIsHttps = false;
        _currentUrl = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.local_fire_department,
                color: Color(0xFFE07A2A), size: 18),
            SizedBox(width: 8),
            Text('Dados de navegação apagados'),
          ]),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF333333),
        ),
      );
    }
  }

  void _onTabsTap() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Gerenciador de abas em breve'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpn = context.watch<VpnService>();
    final topPadding = MediaQuery.of(context).viewPadding.top;

    IconData leadingIcon;
    Color leadingIconColor;
    if (_isEditing || _screen != _Screen.webview) {
      leadingIcon = Icons.search;
      leadingIconColor = _iconGray;
    } else if (_currentIsHttps) {
      leadingIcon = Icons.lock_outline;
      leadingIconColor = _iconGray;
    } else {
      leadingIcon = Icons.public;
      leadingIconColor = _iconGray;
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFDFE9FF),
      extendBody: true,
      extendBodyBehindAppBar: true,
      endDrawer: _SettingsDrawer(
        accent: _accent,
        vpn: vpn,
        onBurnTap: () {
          Navigator.pop(context);
          _burnAll();
        },
      ),
      body: Stack(
        children: [
          // GRADIENTE OCUPA TODA A TELA (inclusive atrás da status bar)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFDFE9FF),
                    Color(0xFFEDE7F6),
                    Color(0xFFE0F7FA),
                  ],
                ),
              ),
            ),
          ),
          // Blobs decorativos
          Positioned(
            top: -80, left: -60,
            child: _Blob(size: 280, color: const Color(0xFFB39DDB)),
          ),
          Positioned(
            top: 200, right: -60,
            child: _Blob(size: 220, color: const Color(0xFF80DEEA)),
          ),
          Positioned(
            bottom: 200, left: -40,
            child: _Blob(size: 200, color: const Color(0xFFF48FB1)),
          ),
          // Corpo principal - top: 0 (sem topPadding)
          Positioned.fill(
            top: 0, // <-- AGORA OCUPA TODA A TELA
            child: _buildBody(),
          ),
          // Pílula flutuante - mantém topPadding para não ficar atrás do notch
          Positioned(
            top: topPadding + 8,
            left: 12,
            right: 12,
            child: _FloatingPill(
              controller: _searchController,
              focusNode: _searchFocus,
              accent: _accent,
              isEditing: _isEditing,
              isWebLoading: _webLoading,
              webProgress: _webProgress,
              blockedCount: _blockedCount,
              showBack: _screen != _Screen.home,
              leadingIcon: leadingIcon,
              leadingIconColor: leadingIconColor,
              vpnActive: vpn.isActive,
              onSubmit: _onSubmit,
              onBack: _goBack,
              onMenuTap: () => _scaffoldKey.currentState?.openEndDrawer(),
              onFireTap: _burnAll,
              onTabsTap: _onTabsTap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        // WebView
        Offstage(
          offstage: _screen != _Screen.webview,
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri('about:blank')),
            initialSettings: _webSettings,
            onWebViewCreated: (c) => _webController = c,
            onLoadStart: (c, url) =>
                setState(() { _webLoading = true; _webProgress = 0; }),
            onLoadStop: (c, url) {
              final u = url?.toString() ?? '';
              if (u.isNotEmpty && u != 'about:blank') {
                // Injeção múltipla para garantir
                _injectHideHeaderCss(c);
                Timer(const Duration(milliseconds: 500), () => _injectHideHeaderCss(c));
                Timer(const Duration(seconds: 1), () => _injectHideHeaderCss(c));
                Timer(const Duration(seconds: 2), () => _injectHideHeaderCss(c));
                setState(() {
                  _webLoading = false;
                  _webProgress = 1;
                  _currentIsHttps = u.startsWith('https://');
                  _currentUrl = u;
                  if (!_searchFocus.hasFocus) {
                    _searchController.text = _domainOnly(u);
                  }
                });
              }
            },
            onProgressChanged: (c, p) {
              setState(() => _webProgress = p / 100.0);
              if (p >= 70) {
                _injectHideHeaderCss(c);
              }
            },
            shouldOverrideUrlLoading: (c, action) async {
              final url = action.request.url?.toString() ?? '';
              if (SearxNGConfig.isTracker(url)) {
                setState(() => _blockedCount++);
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
            shouldInterceptRequest: (c, request) async {
              final url = request.url.toString();
              if (SearxNGConfig.isTracker(url)) {
                setState(() => _blockedCount++);
                return WebResourceResponse(
                  contentType: 'text/plain',
                  statusCode: 200,
                  data: Uint8List(0),
                );
              }
              return null;
            },
          ),
        ),
        // Home
        if (_screen == _Screen.home)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88, height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.9), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7C4DFF).withOpacity(0.15),
                        blurRadius: 32,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.shield,
                      size: 44, color: Color(0xFF80DEEA)),
                ),
                const SizedBox(height: 18),
                const Text(
                  'SearxGo',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A3E),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Busca privada — sem rastreadores',
                  style: TextStyle(
                    fontSize: 14,
                    color: const Color(0xFF3C3C64).withOpacity(0.55),
                  ),
                ),
              ],
            ),
          ),
        // Resultados
        if (_screen == _Screen.results)
          _isSearching
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1A1A2E)))
              : _errorMsg != null
                  ? Center(
                      child: Text(_errorMsg!,
                          style: const TextStyle(color: Colors.redAccent)))
                  : _searchResponse != null
                      ? _ResultsScreen(
                          response: _searchResponse!,
                          accent: _accent,
                          pageBg: Colors.transparent,
                          cardBg: _cardBg,
                          cardBorder: _cardBorder,
                          textMain: _textMain,
                          textSub: _textSub,
                          onResultTap: _loadInWebView,
                          onSuggestionTap: _doSearch,
                        )
                      : const SizedBox.shrink(),
      ],
    );
  }
}

// ================================================================
//  Blob decorativo
// ================================================================
class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.45),
        shape: BoxShape.circle,
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: const SizedBox.expand(),
      ),
    );
  }
}

// ================================================================
//  Pílula flutuante
// ================================================================
class _FloatingPill extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color accent;
  final bool isEditing, isWebLoading, showBack, vpnActive;
  final double webProgress;
  final int blockedCount;
  final IconData leadingIcon;
  final Color leadingIconColor;
  final ValueChanged<String> onSubmit;
  final VoidCallback onBack, onMenuTap, onFireTap, onTabsTap;

  const _FloatingPill({
    required this.controller,
    required this.focusNode,
    required this.accent,
    required this.isEditing,
    required this.isWebLoading,
    required this.webProgress,
    required this.blockedCount,
    required this.showBack,
    required this.leadingIcon,
    required this.leadingIconColor,
    required this.vpnActive,
    required this.onSubmit,
    required this.onBack,
    required this.onMenuTap,
    required this.onFireTap,
    required this.onTabsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (showBack)
              _PillBtn(
                onTap: onBack,
                child: const Icon(Icons.arrow_back,
                    color: Color(0xFF5F5F5F), size: 20),
              ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.82),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isEditing
                            ? accent
                            : Colors.white.withOpacity(0.95),
                        width: isEditing ? 1.5 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 16),
                        Icon(leadingIcon, size: 16, color: leadingIconColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: controller,
                            focusNode: focusNode,
                            onTap: () {
                              controller.selection = TextSelection(
                                baseOffset: 0,
                                extentOffset: controller.text.length,
                              );
                            },
                            onSubmitted: onSubmit,
                            textInputAction: TextInputAction.go,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            style: const TextStyle(
                                color: Colors.black87, fontSize: 16),
                            decoration: const InputDecoration(
                              hintText: 'Pesquisar',
                              hintStyle: TextStyle(
                                  color: Color(0xFF8A8A8A), fontSize: 16),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        if (vpnActive && !isEditing)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.vpn_lock,
                                      size: 12, color: Colors.green),
                                  SizedBox(width: 3),
                                  Text('VPN',
                                      style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        if (blockedCount > 0 && !isEditing)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield, size: 12, color: accent),
                                const SizedBox(width: 2),
                                Text('$blockedCount',
                                    style: TextStyle(
                                        color: accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        else
                          const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _PillBtn(
              onTap: onFireTap,
              child: const Icon(Icons.local_fire_department,
                  color: Color(0xFFE07A2A), size: 22),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: onTabsTap,
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                      color: const Color(0xFF5F5F5F).withOpacity(0.4),
                      width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Text('1',
                    style: TextStyle(
                        color: Color(0xFF5F5F5F),
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 4),
            _PillBtn(
              onTap: onMenuTap,
              child: const Icon(Icons.menu,
                  color: Color(0xFF5F5F5F), size: 22),
            ),
          ],
        ),
        if (isWebLoading && webProgress > 0 && webProgress < 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: webProgress,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF1A73E8)),
                minHeight: 3,
              ),
            ),
          ),
      ],
    );
  }
}

class _PillBtn extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  const _PillBtn({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.75),
              shape: BoxShape.circle,
              border: Border.all(
                  color: Colors.white.withOpacity(0.9), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

// ================================================================
//  Resultados
// ================================================================
class _ResultsScreen extends StatelessWidget {
  final SearchResponse response;
  final Color accent, pageBg, cardBg, cardBorder, textMain, textSub;
  final ValueChanged<String> onResultTap;
  final ValueChanged<String> onSuggestionTap;

  const _ResultsScreen({
    required this.response,
    required this.accent,
    required this.pageBg,
    required this.cardBg,
    required this.cardBorder,
    required this.textMain,
    required this.textSub,
    required this.onResultTap,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: response.results.length +
          (response.suggestions.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == response.results.length) {
          return _SuggestionsRow(
            suggestions: response.suggestions,
            accent: accent,
            onTap: onSuggestionTap,
          );
        }
        final r = response.results[index];
        return _ResultCard(
          result: r,
          accent: accent,
          cardBg: cardBg,
          cardBorder: cardBorder,
          textMain: textMain,
          textSub: textSub,
          onTap: () => onResultTap(r.url),
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  final SearchResult result;
  final Color accent, cardBg, cardBorder, textMain, textSub;
  final VoidCallback onTap;

  const _ResultCard({
    required this.result,
    required this.accent,
    required this.cardBg,
    required this.cardBorder,
    required this.textMain,
    required this.textSub,
    required this.onTap,
  });

  String get _domain {
    try {
      return Uri.parse(result.url).host.replaceFirst('www.', '');
    } catch (_) {
      return result.url;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg.withOpacity(0.75),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.language, size: 12, color: textSub),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_domain,
                      style: TextStyle(color: textSub, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(result.engine,
                    style: TextStyle(
                        color: textSub.withOpacity(0.6), fontSize: 10)),
              ],
            ),
            const SizedBox(height: 6),
            Text(result.title,
                style: const TextStyle(
                  color: Color(0xFF1558D6),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                )),
            if (result.content.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(result.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: textMain, fontSize: 14, height: 1.4)),
            ],
            if (result.publishedDate != null) ...[
              const SizedBox(height: 4),
              Text(result.publishedDate!,
                  style: TextStyle(color: textSub, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionsRow extends StatelessWidget {
  final List<String> suggestions;
  final Color accent;
  final ValueChanged<String> onTap;

  const _SuggestionsRow({
    required this.suggestions,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sugestões',
              style: TextStyle(color: Color(0xFF5F5F5F), fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map((s) => GestureDetector(
                      onTap: () => onTap(s),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.7),
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.9)),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(s,
                                style: const TextStyle(
                                    color: Color(0xFF1558D6),
                                    fontSize: 13)),
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ================================================================
//  Drawer
// ================================================================
class _SettingsDrawer extends StatelessWidget {
  final Color accent;
  final VpnService vpn;
  final VoidCallback onBurnTap;

  const _SettingsDrawer({
    required this.accent,
    required this.vpn,
    required this.onBurnTap,
  });

  static const Color _iconGray = Color(0xFF5F5F5F);

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFFF5F5F5),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: const Color(0xFFEEEEEE),
              child: Row(
                children: [
                  Icon(Icons.shield, color: accent, size: 22),
                  const SizedBox(width: 10),
                  Text(SearxNGConfig.appName,
                      style: TextStyle(
                          color: accent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: vpn.isActive
                    ? Colors.green.withOpacity(0.08)
                    : Colors.red.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: vpn.isActive
                      ? Colors.green.withOpacity(0.3)
                      : Colors.red.withOpacity(0.2),
                ),
              ),
              child: ListTile(
                leading: Icon(Icons.vpn_lock,
                    color: vpn.isActive ? Colors.green : Colors.red,
                    size: 22),
                title: Text('VPN — V2Ray VLESS',
                    style: TextStyle(
                        color: vpn.isActive ? Colors.green : _iconGray,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(vpn.status,
                    style: TextStyle(
                        color: vpn.isActive
                            ? Colors.green.withOpacity(0.8)
                            : const Color(0xFF8A8A8A),
                        fontSize: 12)),
                trailing: vpn.isConnecting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.green))
                    : Switch(
                        value: vpn.isActive,
                        onChanged: (_) => vpn.toggle(),
                        activeColor: Colors.green,
                      ),
              ),
            ),
            const Divider(color: Color(0xFFE0E0E0), height: 16),
            ListTile(
              leading: const Icon(Icons.local_fire_department,
                  color: Color(0xFFE07A2A), size: 22),
              title: const Text('Apagar dados de navegação',
                  style: TextStyle(
                      color: Color(0xFFE07A2A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              subtitle: const Text(
                  'Cookies, cache, histórico e armazenamento',
                  style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 12)),
              trailing: const Icon(Icons.chevron_right,
                  color: Color(0xFFCCCCCC), size: 18),
              onTap: onBurnTap,
            ),
            const Divider(color: Color(0xFFE0E0E0), height: 1),
            const SizedBox(height: 8),
            _item(Icons.tune, 'Configurações do navegador', _iconGray,
                () => Navigator.pop(context)),
            _item(Icons.search, 'Instância SearxNG', _iconGray,
                () => Navigator.pop(context)),
            _item(Icons.security, 'Privacidade & Trackers', _iconGray,
                () => Navigator.pop(context)),
            _item(Icons.info_outline, 'Sobre', _iconGray,
                () => Navigator.pop(context)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(SearxNGConfig.baseUrl,
                  style: const TextStyle(
                      color: Color(0xFFAAAAAA), fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color, size: 20),
      title: Text(label, style: TextStyle(color: color, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right,
          color: Color(0xFFCCCCCC), size: 18),
      onTap: onTap,
    );
  }
}
