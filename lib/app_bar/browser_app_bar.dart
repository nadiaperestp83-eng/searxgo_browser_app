import 'package:flutter/material.dart';
import 'package:flutter_browser/app_bar/desktop_app_bar.dart';
import 'package:flutter_browser/app_bar/find_on_page_app_bar.dart';
import 'package:flutter_browser/app_bar/webview_tab_app_bar.dart';
import 'package:flutter_browser/util.dart';

class BrowserAppBar extends StatefulWidget implements PreferredSizeWidget {
  BrowserAppBar({super.key})
      // Ajustamos o tamanho para não deixar espaço extra de status bar no cálculo do Scaffold
      : preferredSize =
            Size.fromHeight(Util.isMobile() ? kToolbarHeight : 90.0);

  @override
  State<BrowserAppBar> createState() => _BrowserAppBarState();

  @override
  final Size preferredSize;
}

class _BrowserAppBarState extends State<BrowserAppBar> {
  bool _isFindingOnPage = false;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [];

    if (Util.isDesktop()) {
      children.add(const DesktopAppBar());
    }

    children.add(_isFindingOnPage
        ? FindOnPageAppBar(
            hideFindOnPage: () {
              setState(() {
                _isFindingOnPage = false;
              });
            },
          )
        : WebViewTabAppBar(
            showFindOnPage: () {
              setState(() {
                _isFindingOnPage = true;
              });
            },
          ));

    // O MediaQuery.removePadding remove o espaço que o Scaffold 
    // reserva automaticamente para a barra de status do sistema.
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: Column(
        children: children,
      ),
    );
  }
}
