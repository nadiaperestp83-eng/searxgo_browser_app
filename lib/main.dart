import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'searxng_config.dart';
import 'searxgo_browser.dart';
import 'vpn_service.dart';
import 'services/tab_manager.dart';
import 'services/search_engine_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  if (!kReleaseMode && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  final tabManager = TabManager();
  final searchEngineProvider = SearchEngineProvider();
  // Restaura abas e buscador salvos antes de desenhar a tela, para não
  // "piscar" o estado default e depois trocar para o restaurado.
  await Future.wait([tabManager.restore(), searchEngineProvider.restore()]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VpnService()),
        ChangeNotifierProvider.value(value: tabManager),
        ChangeNotifierProvider.value(value: searchEngineProvider),
      ],
      child: const SearxGoApp(),
    ),
  );
}

class SearxGoApp extends StatelessWidget {
  const SearxGoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: SearxNGConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          toolbarHeight: 0,
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1A1A2E),
          secondary: Color(0xFF00D4FF),
          surface: Colors.transparent,
          background: Colors.transparent,
        ),
        splashFactory: NoSplash.splashFactory,
        useMaterial3: true,
      ),
      builder: (context, child) {
        // Remove qualquer AppBar/header que o sistema injete
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
      home: const SearxGoBrowser(),
    );
  }
}
