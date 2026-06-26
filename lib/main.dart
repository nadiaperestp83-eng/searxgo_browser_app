import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'searxng_config.dart';
import 'searxgo_browser.dart';
import 'vpn_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  runApp(
    ChangeNotifierProvider(
      create: (_) => VpnService(),
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
        scaffoldBackgroundColor: const Color(0xFFEEEEEE),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF1A1A2E),
          secondary: Color(0xFF00D4FF),
        ),
        splashFactory: NoSplash.splashFactory,
      ),
      home: const SearxGoBrowser(),
    );
  }
}
