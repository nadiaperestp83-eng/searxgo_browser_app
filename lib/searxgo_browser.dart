import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'searxng_config.dart';

class SearxGoBrowser extends StatefulWidget {
  const SearxGoBrowser({Key? key}) : super(key: key);

  @override
  State<SearxGoBrowser> createState() => _SearxGoBrowserState();
}

class _SearxGoBrowserState extends State<SearxGoBrowser> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  InAppWebViewController? _webController;

  double _loadProgress = 0;
  bool _isLoading = false;
  bool _isEditing = false;
  int _blockedCount = 0;

  final InAppWebViewSettings _webSettings = InAppWebViewSettings(
    useShouldOverrideUrlLoading: true,
    incognito: true,
    cacheEnabled: false,
    clearCache: true,
    userAgent:
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  );

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(
        () => setState(() => _isEditing = _searchFocus.hasFocus));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _navigate(String input) {
    _searchFocus.unfocus();
    _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(SearxNGConfig.resolveInput(input))),
    );
  }

  void _updateBar(String url) {
    if (!_searchFocus.hasFocus) {
      _searchController.text =
          url.replaceFirst('https://', '').replaceFirst('http://', '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final barColor = Color(SearxNGConfig.primaryColor);
    final accent = Color(SearxNGConfig.accentColor);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              // ── WebView (embaixo) ──────────────────────────
              Positioned.fill(
                top: 58,
                child: InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: WebUri(SearxNGConfig.homeUrl)),
                  initialSettings: _webSettings,
                  onWebViewCreated: (c) => _webController = c,
                  onLoadStart: (c, url) {
                    setState(() { _isLoading = true; _loadProgress = 0; });
                    _updateBar(url?.toString() ?? '');
                  },
                  onLoadStop: (c, url) {
                    setState(() => _isLoading = false);
                    _updateBar(url?.toString() ?? '');
                  },
                  onProgressChanged: (c, p) =>
                      setState(() => _loadProgress = p / 100.0),
                  shouldOverrideUrlLoading: (c, action) async {
                    final url = action.request.url?.toString() ?? '';
                    if (SearxNGConfig.isTracker(url)) {
                      setState(() => _blockedCount++);
                      return NavigationActionPolicy.CANCEL;
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                ),
              ),

              // ── Barra fixa (em cima, sempre visível) ───────
              Positioned(
                top: 0, left: 0, right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 54,
                      color: barColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          // Home
                          IconButton(
                            onPressed: () {
                              _searchController.clear();
                              _webController?.loadUrl(
                                urlRequest: URLRequest(
                                    url: WebUri(SearxNGConfig.homeUrl)),
                              );
                            },
                            icon: const Text('🔍',
                                style: TextStyle(fontSize: 18)),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36),
                          ),

                          // Campo de busca
                          Expanded(
                            child: Container(
                              height: 36,
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(18),
                                border: _isEditing
                                    ? Border.all(color: accent, width: 1.5)
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  const SizedBox(width: 10),
                                  Icon(Icons.lock, size: 13, color: accent),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      focusNode: _searchFocus,
                                      onTap: () {
                                        _searchController.selection =
                                            TextSelection(
                                          baseOffset: 0,
                                          extentOffset:
                                              _searchController.text.length,
                                        );
                                      },
                                      onSubmitted: _navigate,
                                      textInputAction: TextInputAction.go,
                                      keyboardType: TextInputType.url,
                                      autocorrect: false,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 14),
                                      decoration: InputDecoration(
                                        hintText: 'Buscar ou digitar URL...',
                                        hintStyle: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.4),
                                            fontSize: 14),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                  if (_isEditing)
                                    GestureDetector(
                                      onTap: () => _searchController.clear(),
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: Icon(Icons.close,
                                            size: 15,
                                            color: Colors.white54),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // Badge trackers
                          if (_blockedCount > 0)
                            Container(
                              margin: const EdgeInsets.only(right: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: accent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: accent.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield,
                                      size: 11, color: accent),
                                  const SizedBox(width: 2),
                                  Text('$_blockedCount',
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),

                          // Navegação
                          _btn(Icons.arrow_back_ios_new,
                              () => _webController?.goBack()),
                          _btn(Icons.arrow_forward_ios,
                              () => _webController?.goForward()),
                          _btn(Icons.refresh,
                              () => _webController?.reload()),
                        ],
                      ),
                    ),
                    // Barra de progresso
                    _isLoading
                        ? LinearProgressIndicator(
                            value: _loadProgress,
                            backgroundColor: Colors.transparent,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(accent),
                            minHeight: 2,
                          )
                        : const SizedBox(height: 2),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 17, color: Colors.white70),
        padding: const EdgeInsets.all(2),
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      );
}
