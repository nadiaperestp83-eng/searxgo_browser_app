// Gerencia a lista de abas em memória + persistência leve (apenas a URL
// e o "modo" de cada aba — home/results/webview) via shared_preferences,
// para que as abas sobrevivam a um restart do app.
//
// Importante: o TabManager NÃO guarda o InAppWebViewController nem o
// estado de UI (progresso, cards de resultado, etc). Quem faz isso é
// _SearxGoBrowserState, chamando `saveActiveTabState()` antes de trocar
// de aba e lendo `active` depois de trocar. Isso mantém esta classe
// pequena e fácil de testar isoladamente.
//
// Caminho: lib/services/tab_manager.dart

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/browser_tab.dart';

class TabManager extends ChangeNotifier {
  static const _prefsUrlsKey = 'searxgo_tabs_v1';
  static const _prefsScreensKey = 'searxgo_tabs_screens_v1';
  static const _prefsActiveKey = 'searxgo_active_tab_v1';

  static const _uuid = Uuid();

  final List<BrowserTab> tabs = [];
  int activeIndex = 0;
  bool restored = false;

  BrowserTab get active => tabs[activeIndex];

  // ── Restaura as abas salvas (ou cria a primeira aba, se não houver) ──
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final urls = prefs.getStringList(_prefsUrlsKey);
    final screens = prefs.getStringList(_prefsScreensKey);

    tabs.clear();
    if (urls == null || urls.isEmpty) {
      tabs.add(BrowserTab(id: _uuid.v4()));
    } else {
      for (var i = 0; i < urls.length; i++) {
        final url = urls[i];
        final screenName = (screens != null && i < screens.length)
            ? screens[i]
            : TabScreen.home.name;
        final screen = TabScreen.values.firstWhere(
          (s) => s.name == screenName,
          orElse: () => TabScreen.home,
        );
        tabs.add(BrowserTab(
          id: _uuid.v4(),
          url: url,
          title: url.isEmpty ? 'Nova aba' : _domainOf(url),
          screen: url.isEmpty ? TabScreen.home : screen,
        ));
      }
    }

    activeIndex = prefs.getInt(_prefsActiveKey) ?? 0;
    if (activeIndex < 0 || activeIndex >= tabs.length) activeIndex = 0;

    restored = true;
    notifyListeners();
  }

  Future<void> persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsUrlsKey, tabs.map((t) => t.url).toList());
    await prefs.setStringList(
        _prefsScreensKey, tabs.map((t) => t.screen.name).toList());
    await prefs.setInt(_prefsActiveKey, activeIndex);
  }

  String _domainOf(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isEmpty ? url : host.replaceFirst('www.', '');
    } catch (_) {
      return url;
    }
  }

  // ── Cria uma nova aba em branco e a torna ativa ──────────────
  void newTab() {
    tabs.add(BrowserTab(id: _uuid.v4()));
    activeIndex = tabs.length - 1;
    notifyListeners();
    persist();
  }

  // ── Fecha uma aba (nunca deixa a lista vazia) ────────────────
  void closeTab(int index) {
    if (index < 0 || index >= tabs.length || tabs.length <= 1) return;
    tabs.removeAt(index);
    if (activeIndex >= tabs.length) {
      activeIndex = tabs.length - 1;
    } else if (activeIndex > index) {
      activeIndex--;
    }
    notifyListeners();
    persist();
  }

  void switchTo(int index) {
    if (index < 0 || index >= tabs.length || index == activeIndex) return;
    activeIndex = index;
    notifyListeners();
    persist();
  }

  // ── Alterna ciclicamente para a próxima aba ──────────────────
  void cycleNext() {
    if (tabs.length < 2) return;
    switchTo((activeIndex + 1) % tabs.length);
  }
}
