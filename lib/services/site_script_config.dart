// Configuração de "limpeza" de JS/CSS por site — cada buscador externo
// (DuckDuckGo, Brave Search, Startpage, Mojeek) tem seus próprios banners
// de "instale o app"/"baixe nosso navegador". Em vez de um script genérico
// gigante misturando tudo, cada host tem sua config isolada aqui, então dá
// pra ajustar um buscador sem arriscar quebrar os outros — foi exatamente
// esse tipo de mistura (um script genérico rodando em qualquer site) que
// causou o bug de tela em branco na Britannica antes.
//
// IMPORTANTE sobre segurança do heurístico: por definição, NUNCA usamos um
// seletor genérico do tipo '[class*="banner"]' sozinho — isso já apagou
// conteúdo real de sites de terceiros no passado. Toda remoção aqui exige
// UM dos dois:
//   (a) um seletor específico e conhecido deste host, OU
//   (b) o heurístico por posição + tamanho + texto (abaixo), que só ESCONDE
//       (display:none, não remove do DOM) elementos pequenos (altura <
//       220px), fixos/perto da borda da tela, cujo texto bate com uma frase
//       de instalação. Nunca mexe em blocos grandes de layout/conteúdo.
//
// OBS HONESTA: os `knownSelectors` abaixo são "melhor esforço" — padrões
// comuns de mercado (smart banners, app-install banners) — não foram
// confirmados inspecionando o DOM ao vivo de cada site (o ambiente onde
// isso foi escrito não tem acesso de navegador à internet). Se algum
// banner escapar, ajuste a lista de `knownSelectors` do host aqui; o
// heurístico como um todo é o fallback que deve pegar a maioria dos casos
// mesmo que os seletores exatos não batam.
//
// Caminho: lib/services/site_script_config.dart

class SiteScriptConfig {
  final String host;

  /// Seletores CSS específicos e conhecidos deste site.
  final List<String> knownSelectors;

  /// Ativa o heurístico genérico (posição + tamanho + texto) como reforço
  /// para banners que não batem com os seletores conhecidos.
  final bool useHeuristic;

  const SiteScriptConfig({
    required this.host,
    this.knownSelectors = const [],
    this.useHeuristic = true,
  });

  // Frases comuns de banners de instalação (PT + EN), usadas pelo
  // heurístico. Comparação é case-insensitive e por "contém".
  static const List<String> _installMarkers = [
    'instale o aplicativo',
    'instale nosso aplicativo',
    'instale o app',
    'baixe nosso navegador',
    'baixe o app',
    'baixe o aplicativo',
    'baixe nosso app',
    'get the app',
    'install the app',
    'install our app',
    'download the app',
    'download our browser',
    'try our browser',
    'try the app',
    'open in app',
    'abrir no app',
  ];

  static const Map<String, SiteScriptConfig> _configs = {
    'duckduckgo.com': SiteScriptConfig(
      host: 'duckduckgo.com',
      knownSelectors: [
        '.mobile-download-app-banner',
        '[data-testid="mobile-app-banner"]',
        '.js-download-the-app-banner',
        '#app-banner',
        '.app-banner',
      ],
    ),
    'search.brave.com': SiteScriptConfig(
      host: 'search.brave.com',
      knownSelectors: [
        '.app-download-banner',
        '[data-testid="app-banner"]',
        '.brave-download-banner',
        '.download-banner',
      ],
    ),
    'www.startpage.com': SiteScriptConfig(
      host: 'www.startpage.com',
      knownSelectors: [
        '.app-promo-banner',
        '.download-app-banner',
        '.app-banner',
      ],
    ),
    'www.mojeek.com': SiteScriptConfig(
      host: 'www.mojeek.com',
      knownSelectors: [
        '.app-banner',
        '.get-app-banner',
      ],
    ),
  };

  static SiteScriptConfig? forHost(String host) => _configs[host];

  /// Monta o JS a ser injetado depois que a página carrega.
  String buildJs() {
    final selectorsJs = knownSelectors.map((s) => "'$s'").join(', ');
    final markersJs = _installMarkers.map((s) => "'$s'").join(', ');

    return """
      (function() {
        function removeKnown() {
          [$selectorsJs].forEach(function(sel) {
            try {
              document.querySelectorAll(sel).forEach(function(el) {
                el.style.display = 'none';
              });
            } catch (e) {}
          });
        }

        function hideByHeuristic() {
          var markers = [$markersJs];
          // Limitado aos filhos/netos diretos de <body>: banners de
          // instalação normalmente são injetados como overlay logo
          // abaixo de <body>, não escondidos fundo no conteúdo. Isso
          // também mantém o custo baixo (não varre a árvore inteira).
          var candidates = document.querySelectorAll('body > *, body > * > *');
          for (var i = 0; i < candidates.length; i++) {
            var el = candidates[i];
            var text = (el.innerText || '').trim().toLowerCase();
            if (!text || text.length > 300) continue;

            var matches = false;
            for (var j = 0; j < markers.length; j++) {
              if (text.indexOf(markers[j]) !== -1) { matches = true; break; }
            }
            if (!matches) continue;

            var rect = el.getBoundingClientRect();
            if (rect.height === 0 || rect.height > 220) continue;

            var nearEdge = rect.top < 120 ||
                (window.innerHeight - rect.bottom) < 160;
            var style = window.getComputedStyle(el);
            var isOverlayish = style.position === 'fixed' || style.position === 'sticky';

            if (nearEdge || isOverlayish) {
              el.style.display = 'none';
            }
          }
        }

        removeKnown();
        ${useHeuristic ? 'hideByHeuristic();' : ''}
      })();
    """;
  }
}
