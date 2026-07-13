import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:http/http.dart' as http;

// ================================================================
//  VpnService — VLESS via flutter_v2ray
//
//  Busca servidores VLESS da lista pública do GitHub (ebrasha)
//  atualizada a cada 30 minutos. Conecta via VPN mode no Android.
//  Todo tráfego do navegador passa pelo túnel quando ativo.
// ================================================================

class VpnService extends ChangeNotifier {
  bool _isActive = false;
  bool _isConnecting = false;
  String _status = 'Desconectado';
  String _serverInfo = '';

  bool get isActive => _isActive;
  bool get isConnecting => _isConnecting;
  String get status => _status;
  String get serverInfo => _serverInfo;

  // URL da lista pública VLESS — atualizada a cada 30min
  static const String _subUrl =
      'https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list'
      '/refs/heads/main/V2Ray-Config-By-EbraSha.txt';

  late final FlutterV2ray _v2ray = FlutterV2ray(
    onStatusChanged: (status) {
      _isActive = status.state == 'CONNECTED';
      _isConnecting = status.state == 'CONNECTING';
      _status = _friendlyStatus(status.state);
      notifyListeners();
    },
  );

  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await _v2ray.initializeV2Ray(
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
    );
    _initialized = true;
  }

  // ── Liga / desliga ───────────────────────────────────────────
  Future<void> toggle() async {
    if (_isConnecting) return;

    if (_isActive) {
      await _disconnect();
    } else {
      await _connect();
    }
  }

  Future<void> _connect() async {
    _isConnecting = true;
    _status = 'Buscando servidor...';
    notifyListeners();

    try {
      await _init();

      // 1. Baixa lista de servidores
      final configs = await _fetchVlessConfigs();
      if (configs.isEmpty) {
        _status = 'Nenhum servidor disponível';
        _isConnecting = false;
        notifyListeners();
        return;
      }

      // 2. Testa os primeiros 5 EM PARALELO, cada um com timeout curto,
      //    pra não travar o app inteiro esperando um servidor público
      //    lento ou fora do ar.
      _status = 'Testando servidores...';
      notifyListeners();

      const _pingTimeout = Duration(seconds: 3);
      final candidates = configs.take(5).toList();

      final results = await Future.wait(
        candidates.map((link) async {
          try {
            final parsed = FlutterV2ray.parseFromURL(link);
            final delay = await _v2ray
                .getServerDelay(config: parsed.getFullConfiguration())
                .timeout(_pingTimeout, onTimeout: () => -1);
            return (parsed, delay);
          } catch (_) {
            return (null, -1);
          }
        }),
      );

      V2RayURL? bestConfig;
      int bestDelay = 9999;
      for (final (parsed, delay) in results) {
        if (parsed != null && delay > 0 && delay < bestDelay) {
          bestDelay = delay;
          bestConfig = parsed;
        }
      }

      if (bestConfig == null) {
        // Nenhum respondeu a tempo — usa o primeiro da lista mesmo assim
        bestConfig = FlutterV2ray.parseFromURL(configs.first);
      }

      // 3. Pede permissão VPN e conecta
      _status = 'Solicitando permissão...';
      notifyListeners();

      final hasPermission = await _v2ray.requestPermission();
      if (!hasPermission) {
        _status = 'Permissão negada';
        _isConnecting = false;
        notifyListeners();
        return;
      }

      _serverInfo = bestConfig.remark.isNotEmpty
          ? bestConfig.remark
          : 'Servidor público';

      await _v2ray.startV2Ray(
        remark: _serverInfo,
        config: bestConfig.getFullConfiguration(),
        blockedApps: null,      // null = protege todos os apps
        bypassSubnets: null,
        proxyOnly: false,       // VPN real, não só proxy local
        notificationDisconnectButtonName: 'Desconectar',
      );
    } catch (e) {
      _status = 'Erro: ${e.toString().split('\n').first}';
      _isActive = false;
      _isConnecting = false;
      debugPrint('V2Ray error: $e');
      notifyListeners();
    }
  }

  Future<void> _disconnect() async {
    _isConnecting = true;
    _status = 'Desconectando...';
    notifyListeners();

    try {
      await _v2ray.stopV2Ray();
    } catch (e) {
      debugPrint('V2Ray stop error: $e');
    } finally {
      _isActive = false;
      _isConnecting = false;
      _status = 'Desconectado';
      _serverInfo = '';
      notifyListeners();
    }
  }

  // ── Baixa e parseia lista VLESS do GitHub ────────────────────
  Future<List<String>> _fetchVlessConfigs() async {
    try {
      final res = await http
          .get(Uri.parse(_subUrl))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];

      // A lista pode ser base64 ou texto direto
      String body;
      try {
        body = utf8.decode(base64.decode(res.body.trim()));
      } catch (_) {
        body = res.body;
      }

      // Filtra só VLESS
      return body
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.startsWith('vless://'))
          .toList();
    } catch (e) {
      debugPrint('Fetch configs error: $e');
      return [];
    }
  }

  String _friendlyStatus(String state) {
    switch (state) {
      case 'CONNECTED':
        return 'Conectado — $_serverInfo';
      case 'CONNECTING':
        return 'Conectando...';
      case 'DISCONNECTED':
        return 'Desconectado';
      case 'WAITING':
        return 'Aguardando...';
      default:
        return state;
    }
  }

  @override
  void dispose() {
    if (_isActive) {
      _v2ray.stopV2Ray().catchError((_) {});
    }
    super.dispose();
  }
}
