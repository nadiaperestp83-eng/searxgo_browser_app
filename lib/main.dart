import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'searxng_config.dart';
import 'searxgo_browser.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && defaultTargetPlatform == TargetPlatform.android) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  runApp(const SearxGoApp());
}

class SearxGoApp extends StatelessWidget {
  const SearxGoApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: SearxNGConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D1A),
        colorScheme: ColorScheme.dark(
          primary: Color(SearxNGConfig.primaryColor),
          secondary: Color(SearxNGConfig.accentColor),
        ),
        splashFactory: NoSplash.splashFactory,
      ),
      home: const SearxGoBrowser(),
    );
  }
}
