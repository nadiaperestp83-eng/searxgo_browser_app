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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
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
    // Sem UI nativa do WebView — só nossa barra Flutter
    supportZoom: true,
    builtInZoomControls: false,
    displayZoomControls: false,
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
    final accent = Color(SearxNGConfig.accentColor);
    final barColor = Color(SearxNGConfig.primaryColor);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,

        // ── Drawer lateral (menu hamburguer) ─────────────────
        endDrawer: _SettingsDrawer(accent: accent, barColor: barColor),

        body: SafeArea(
          child: Stack(
            children: [
              // ── WebView — ocupa tudo abaixo da barra ────────
              Positioned.fill(
                top: 56,
                child: InAppWebView(
                  initialUrlRequest:
                      URLRequest(url: WebUri(SearxNGConfig.homeUrl)),
                  initialSettings: _webSettings,
                  onWebViewCreated: (c) => _webController = c,
                  onLoadStart: (c, url) {
                    setState(() {
                      _isLoading = true;
                      _loadProgress = 0;
                    });
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

              // ── Barra fixa estilo DDG ────────────────────────
              Positioned(
                top: 0, left: 0, right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 52,
                      color: barColor,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          // Campo de busca — igual DDG, ocupa tudo
                          Expanded(
                            child: GestureDetector(
                              onTap: () {
                                _searchFocus.requestFocus();
                                _searchController.selection = TextSelection(
                                  baseOffset: 0,
                                  extentOffset:
                                      _searchController.text.length,
                                );
                              },
                              child: Container(
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: _isEditing
                                      ? Border.all(
                                          color: accent, width: 1.5)
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
                                        controller: _searchController,
                                        focusNode: _searchFocus,
                                        onSubmitted: _navigate,
                                        textInputAction: TextInputAction.go,
                                        keyboardType: TextInputType.url,
                                        autocorrect: false,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14),
                                        decoration: InputDecoration(
                                          hintText:
                                              'Buscar ou digitar URL...',
                                          hintStyle: TextStyle(
                                              color: Colors.white
                                                  .withOpacity(0.4),
                                              fontSize: 14),
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                          // SEM suffixIcon — sem X
                                        ),
                                      ),
                                    ),
                                    // Badge trackers bloqueados
                                    if (_blockedCount > 0 && !_isEditing)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.shield,
                                                size: 12, color: accent),
                                            const SizedBox(width: 2),
                                            Text('$_blockedCount',
                                                style: TextStyle(
                                                    color: accent,
                                                    fontSize: 11,
                                                    fontWeight:
                                                        FontWeight.bold)),
                                          ],
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(width: 6),

                          // Hamburguer — abre drawer de configurações
                          IconButton(
                            onPressed: () =>
                                _scaffoldKey.currentState?.openEndDrawer(),
                            icon: const Icon(Icons.menu,
                                color: Colors.white70, size: 22),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 36, minHeight: 36),
                          ),
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
}

// ================================================================
//  Drawer de configurações (esqueleto — expandir depois)
// ================================================================

class _SettingsDrawer extends StatelessWidget {
  final Color accent;
  final Color barColor;

  const _SettingsDrawer({required this.accent, required this.barColor});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF0D0D1A),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cabeçalho
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              color: barColor,
              child: Row(
                children: [
                  Icon(Icons.shield, color: accent, size: 22),
                  const SizedBox(width: 10),
                  Text(
                    SearxNGConfig.appName,
                    style: TextStyle(
                      color: accent,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Itens — cada um será uma tela de config futura
            _DrawerItem(
              icon: Icons.tune,
              label: 'Configurações do navegador',
              accent: accent,
              onTap: () {
                Navigator.pop(context);
                // TODO: NavBar de configurações (próxima etapa)
              },
            ),
            _DrawerItem(
              icon: Icons.search,
              label: 'Instância SearxNG',
              accent: accent,
              onTap: () {
                Navigator.pop(context);
                // TODO: tela para trocar URL base
              },
            ),
            _DrawerItem(
              icon: Icons.security,
              label: 'Privacidade & Trackers',
              accent: accent,
              onTap: () {
                Navigator.pop(context);
                // TODO: lista de trackers bloqueados
              },
            ),
            _DrawerItem(
              icon: Icons.info_outline,
              label: 'Sobre',
              accent: accent,
              onTap: () {
                Navigator.pop(context);
              },
            ),

            const Spacer(),

            // Rodapé — instância ativa
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                SearxNGConfig.baseUrl,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: accent, size: 20),
      title: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 15),
      ),
      trailing: const Icon(Icons.chevron_right,
          color: Colors.white24, size: 18),
      onTap: onTap,
    );
  }
}
