// Gerencia qual buscador padrão está selecionado, persiste a escolha em
// shared_preferences, e sabe montar a URL de busca de cada um.
//
// Só o SearxNG (self-hosted) expõe uma API JSON que dá pra parsear nos
// cards de resultado customizados (_ResultsScreen). Os demais buscadores
// (DuckDuckGo, Brave Search, Startpage, Mojeek) não têm API JSON pública
// — para esses, `isJsonCapable` é false e o app deve simplesmente
// carregar a página de resultados normal deles dentro da WebView, como
// um navegador comum (ver `_doSearch` em searxgo_browser.dart).
//
// Caminho: lib/services/search_engine_provider.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SearchEngine { searxng, duckduckgo, brave, startpage, mojeek }

extension SearchEngineInfo on SearchEngine {
  String get label {
    switch (this) {
      case SearchEngine.searxng:
        return 'SearxNG (próprio)';
      case SearchEngine.duckduckgo:
        return 'DuckDuckGo';
      case SearchEngine.brave:
        return 'Brave Search';
      case SearchEngine.startpage:
        return 'Startpage';
      case SearchEngine.mojeek:
        return 'Mojeek';
    }
  }

  bool get isJsonCapable => this == SearchEngine.searxng;

  /// Monta a URL de busca deste buscador. [searxBaseUrl] só é usado
  /// quando `this == SearchEngine.searxng`.
  String searchUrl(String query, {required String searxBaseUrl}) {
    final q = Uri.encodeQueryComponent(query);
    switch (this) {
      case SearchEngine.searxng:
        return '$searxBaseUrl/search?q=$q&format=json';
      case SearchEngine.duckduckgo:
        return 'https://duckduckgo.com/?q=$q';
      case SearchEngine.brave:
        return 'https://search.brave.com/search?q=$q';
      case SearchEngine.startpage:
        return 'https://www.startpage.com/sp/search?query=$q';
      case SearchEngine.mojeek:
        return 'https://www.mojeek.com/search?q=$q';
    }
  }
}

class SearchEngineProvider extends ChangeNotifier {
  static const _prefsKey = 'searxgo_search_engine_v1';

  SearchEngine _engine = SearchEngine.searxng;
  SearchEngine get engine => _engine;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefsKey);
    if (stored != null) {
      _engine = SearchEngine.values.firstWhere(
        (e) => e.name == stored,
        orElse: () => SearchEngine.searxng,
      );
      notifyListeners();
    }
  }

  Future<void> setEngine(SearchEngine e) async {
    if (e == _engine) return;
    _engine = e;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, e.name);
  }
}
