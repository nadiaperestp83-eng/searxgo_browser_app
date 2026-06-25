import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'searxng_config.dart';
import 'models/search_result.dart';

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

  // WebView controller
  InAppWebViewController? _webController;

  _Screen _screen = _Screen.home;
  bool _isSearching = false; // loading da API JSON
  bool _isEditing = false;
  double _webProgress = 0;
  bool _webLoading = false;
  int _blockedCount = 0;

  SearchResponse? _searchResponse;
  String? _errorMsg;

  // ── WebView configurado como navegador completo ──────────────
  final InAppWebViewSettings _webSettings = InAppWebViewSettings(
    // Navegador completo
    useShouldOverrideUrlLoading: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    allowFileAccess: true,
    allowContentAccess: true,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    // Privacidade
    incognito: true,
    cacheEnabled: false,
    clearCache: true,
    // Sem controles nativos do WebView
    builtInZoomControls: false,
    displayZoomControls: false,
    supportZoom: true,
    // Sem barra nativa
    disableDefaultErrorPage: false,
    // User agent mobile real
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

  // ── Decide: URL direta ou busca JSON ─────────────────────────
  void _onSubmit(String input) {
    final t = input.trim();
    if (t.isEmpty) return;
    _searchFocus.unfocus();

    if (SearxNGConfig.looksLikeUrl(t)) {
      // É URL — abre WebView diretamente
      final url = SearxNGConfig.toUrl(t);
      _loadInWebView(url);
    } else {
      // É busca — consome API JSON
      _doSearch(t);
    }
  }

  // ── Carrega URL no WebView ───────────────────────────────────
  void _loadInWebView(String url) {
    setState(() {
      _screen = _Screen.webview;
      _webProgress = 0;
      _webLoading = true;
    });
    if (_webController != null) {
      _webController!.loadUrl(
          urlRequest: URLRequest(url: WebUri(url)));
    }
    // Atualiza barra com URL limpa
    _searchController.text =
        url.replaceFirst('https://', '').replaceFirst('http://', '');
  }

  // ── Chama API JSON do SearxNG ────────────────────────────────
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

  // ── Voltar ───────────────────────────────────────────────────
  void _goBack() {
    if (_screen == _Screen.webview) {
      if (_searchResponse != null) {
        setState(() {
          _screen = _Screen.results;
          _searchController.text = _searchResponse!.query;
        });
      } else {
        setState(() {
          _screen = _Screen.home;
          _searchController.clear();
        });
      }
    } else if (_screen == _Screen.results) {
      setState(() {
        _screen = _Screen.home;
        _searchController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Color(SearxNGConfig.accentColor);
    final barColor = Color(SearxNGConfig.primaryColor);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        key: _scaffoldKey,
        // Fundo escuro fixo — elimina tela rosa do tema original
        backgroundColor: const Color(0xFF0D0D1A),
        endDrawer: _SettingsDrawer(accent: accent, barColor: barColor),
        body: SafeArea(
          child: Column(
            children: [
              // ── Barra fixa ───────────────────────────────────
              _TopBar(
                controller: _searchController,
                focusNode: _searchFocus,
                barColor: barColor,
                accent: accent,
                isEditing: _isEditing,
                isWebLoading: _webLoading,
                webProgress: _webProgress,
                blockedCount: _blockedCount,
                showBack: _screen != _Screen.home,
                onSubmit: _onSubmit,
                onBack: _goBack,
                onMenuTap: () =>
                    _scaffoldKey.currentState?.openEndDrawer(),
              ),

              // ── Corpo ────────────────────────────────────────
              Expanded(child: _buildBody(accent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(Color accent) {
    return Stack(
      children: [
        // WebView sempre no DOM, só oculto quando não está ativo
        Offstage(
          offstage: _screen != _Screen.webview,
          child: InAppWebView(
            initialUrlRequest: URLRequest(
                url: WebUri('about:blank')),
            initialSettings: _webSettings,
            onWebViewCreated: (c) => _webController = c,
            // onLoadStop atualiza a barra de endereços
            onLoadStop: (c, url) {
              final u = url?.toString() ?? '';
              if (u.isNotEmpty && u != 'about:blank') {
                setState(() {
                  _webLoading = false;
                  _webProgress = 1;
                  if (!_searchFocus.hasFocus) {
                    _searchController.text = u
                        .replaceFirst('https://', '')
                        .replaceFirst('http://', '');
                  }
                });
              }
            },
            onLoadStart: (c, url) {
              setState(() {
                _webLoading = true;
                _webProgress = 0;
              });
            },
            onProgressChanged: (c, p) =>
                setState(() => _webProgress = p / 100.0),
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

        // Tela home
        if (_screen == _Screen.home)
          _HomeScreen(accent: accent),

        // Resultados JSON
        if (_screen == _Screen.results)
          _isSearching
              ? Center(
                  child: CircularProgressIndicator(color: accent))
              : _errorMsg != null
                  ? Center(
                      child: Text(_errorMsg!,
                          style: const TextStyle(
                              color: Colors.redAccent)))
                  : _searchResponse != null
                      ? _ResultsScreen(
                          response: _searchResponse!,
                          accent: accent,
                          onResultTap: _loadInWebView,
                          onSuggestionTap: _doSearch,
                        )
                      : const SizedBox.shrink(),
      ],
    );
  }
}

// ================================================================
//  Barra fixa estilo DDG
// ================================================================
class _TopBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color barColor, accent;
  final bool isEditing, isWebLoading, showBack;
  final double webProgress;
  final int blockedCount;
  final ValueChanged<String> onSubmit;
  final VoidCallback onBack, onMenuTap;

  const _TopBar({
    required this.controller,
    required this.focusNode,
    required this.barColor,
    required this.accent,
    required this.isEditing,
    required this.isWebLoading,
    required this.webProgress,
    required this.blockedCount,
    required this.showBack,
    required this.onSubmit,
    required this.onBack,
    required this.onMenuTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 52,
          color: barColor,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              if (showBack)
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white70, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                      minWidth: 32, minHeight: 32),
                ),

              // Campo de busca
              Expanded(
                child: Container(
                  height: 38,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: isEditing
                        ? Border.all(color: accent, width: 1.5)
                        : null,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      Icon(Icons.lock_outline,
                          size: 13, color: accent),
                      const SizedBox(width: 6),
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
                              color: Colors.white, fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Buscar ou digitar URL...',
                            hintStyle: TextStyle(
                                color: Colors.white.withOpacity(0.4),
                                fontSize: 14),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (blockedCount > 0 && !isEditing)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield,
                                  size: 12, color: accent),
                              const SizedBox(width: 2),
                              Text('$blockedCount',
                                  style: TextStyle(
                                      color: accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),

              // Hamburguer
              IconButton(
                onPressed: onMenuTap,
                icon: const Icon(Icons.menu,
                    color: Colors.white70, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 36, minHeight: 36),
              ),
            ],
          ),
        ),
        // Progresso do WebView
        isWebLoading && webProgress > 0 && webProgress < 1
            ? LinearProgressIndicator(
                value: webProgress,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(accent),
                minHeight: 2,
              )
            : const SizedBox(height: 2),
      ],
    );
  }
}

// ================================================================
//  Tela inicial
// ================================================================
class _HomeScreen extends StatelessWidget {
  final Color accent;
  const _HomeScreen({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D1A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield, size: 64,
                color: accent.withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(
              SearxNGConfig.appName,
              style: TextStyle(
                color: accent,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Busca privada — sem rastreadores',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.4),
                  fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
//  Resultados JSON em cards
// ================================================================
class _ResultsScreen extends StatelessWidget {
  final SearchResponse response;
  final Color accent;
  final ValueChanged<String> onResultTap;
  final ValueChanged<String> onSuggestionTap;

  const _ResultsScreen({
    required this.response,
    required this.accent,
    required this.onResultTap,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D1A),
      child: ListView.builder(
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
              onTap: () => onResultTap(r.url));
        },
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final SearchResult result;
  final Color accent;
  final VoidCallback onTap;

  const _ResultCard(
      {required this.result,
      required this.accent,
      required this.onTap});

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
        margin: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.language,
                    size: 12, color: Colors.white38),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(_domain,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                      overflow: TextOverflow.ellipsis),
                ),
                Text(result.engine,
                    style: TextStyle(
                        color: accent.withOpacity(0.5),
                        fontSize: 10)),
              ],
            ),
            const SizedBox(height: 6),
            Text(result.title,
                style: TextStyle(
                    color: accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            if (result.content.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(result.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.65),
                      fontSize: 13,
                      height: 1.4)),
            ],
            if (result.publishedDate != null) ...[
              const SizedBox(height: 5),
              Text(result.publishedDate!,
                  style: const TextStyle(
                      color: Colors.white24, fontSize: 11)),
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

  const _SuggestionsRow(
      {required this.suggestions,
      required this.accent,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Sugestões',
              style:
                  TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map((s) => GestureDetector(
                      onTap: () => onTap(s),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: accent.withOpacity(0.3)),
                          borderRadius:
                              BorderRadius.circular(16),
                        ),
                        child: Text(s,
                            style: TextStyle(
                                color: accent, fontSize: 13)),
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
//  Drawer configurações
// ================================================================
class _SettingsDrawer extends StatelessWidget {
  final Color accent, barColor;
  const _SettingsDrawer(
      {required this.accent, required this.barColor});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D0D1A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: barColor,
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
            _item(Icons.tune, 'Configurações do navegador',
                accent, () => Navigator.pop(context)),
            _item(Icons.search, 'Instância SearxNG', accent,
                () => Navigator.pop(context)),
            _item(Icons.security, 'Privacidade & Trackers',
                accent, () => Navigator.pop(context)),
            _item(Icons.info_outline, 'Sobre', accent,
                () => Navigator.pop(context)),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(SearxNGConfig.baseUrl,
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _item(IconData icon, String label, Color accent,
      VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: accent, size: 20),
      title: Text(label,
          style: const TextStyle(
              color: Colors.white70, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right,
          color: Colors.white24, size: 18),
      onTap: onTap,
    );
  }
}
