// Modelo leve de uma aba do navegador.
//
// De propósito, isso NÃO guarda o InAppWebViewController nem o estado
// completo de renderização (progresso, resultados de busca, etc) — isso
// continua vivendo em _SearxGoBrowserState, que salva/restaura os campos
// relevantes aqui sempre que o usuário troca de aba. Isso mantém o
// TabManager simples (uma lista em memória + persistência via
// shared_preferences) e evita termos que manter N WebViews vivas ao
// mesmo tempo — cada troca de aba recarrega a URL salva.
//
// Caminho: lib/models/browser_tab.dart

enum TabScreen { home, results, webview }

class BrowserTab {
  final String id;
  String url;
  String title;
  TabScreen screen;

  BrowserTab({
    required this.id,
    this.url = '',
    this.title = 'Nova aba',
    this.screen = TabScreen.home,
  });
}
