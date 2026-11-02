import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/ads_service.dart';
import '../services/api.dart';
import '../services/storage.dart';
import '../services/vpn_engine.dart';

enum ConnStatus { disconnected, connecting, connected, reconnecting, disconnecting }

/// Central app state: plan/config from the server, connection lifecycle,
/// protocol fallback, node failover and auto-reconnect.
class AppState extends ChangeNotifier {
  AppState({required this.api, required this.storage, required this.engine, required this.ads});

  final Api api;
  final Storage storage;
  final VpnEngine engine;
  final AdsService ads;

  Bootstrap? boot;
  bool loading = true;
  String? fatalError;       // shown on the splash/error screen
  String? message;          // transient banner on home
  String? blockingCode;     // quota_exceeded / pro_required → paywall prompt

  ConnStatus status = ConnStatus.disconnected;
  SessionConfig? session;
  DateTime? connectedAt;
  bool _userWantsConnection = false;
  final Set<String> _failedNodes = {};
  Timer? _ticker;
  Timer? _health;
  Timer? _refresh;
  int _healthFailures = 0;
  int _reconnectAttempts = 0;
  StreamSubscription<EngineState>? _engineSub;
  bool _busy = false;

  String get region => storage.region;
  String get protocol => storage.protocol;
  bool get autoReconnect => storage.autoReconnect;
  bool get isPro => boot?.plan.isPro ?? false;
  bool get showAds => !isPro && (boot?.ads.enabled ?? false);

  Duration get elapsed => connectedAt == null ? Duration.zero : DateTime.now().difference(connectedAt!);

  Region? get selectedRegion {
    final b = boot;
    if (b == null || region == 'auto') return null;
    for (final r in b.regions) {
      if (r.code == region) return r;
    }
    return null;
  }

  // ------------------------------------------------------------------ init
  Future<void> init() async {
    loading = true;
    notifyListeners();
    await engine.init();
    _engineSub ??= engine.states.listen(_onEngineState);
    await refresh(silent: false);
    if (showAds) {
      await ads.init();
      ads.preloadInterstitial();
    }
    loading = false;
    notifyListeners();
    if (storage.autoConnectOnLaunch && boot != null && engine.state == EngineState.disconnected) {
      unawaited(connect());
    }
  }

  Future<void> refresh({bool silent = true}) async {
    try {
      boot = await api.bootstrap(storage.installId);
      fatalError = null;
      // Selected region may have become locked (e.g. Pro expired).
      final sel = selectedRegion;
      if (region != 'auto' && (sel == null || sel.locked)) storage.region = 'auto';
      if (protocol != 'auto' && !(boot!.allowedProtocols.contains(protocol))) storage.protocol = 'auto';
    } on ApiException catch (e) {
      if (!silent && boot == null) {
        // Allow offline/censored start if we have cached sessions.
        final hasCache = storage.cachedSession('vless') != null || storage.cachedSession('wireguard') != null;
        fatalError = hasCache ? null : e.message;
        message = hasCache ? 'Server unreachable — using saved servers.' : null;
      }
      if (e.code == 'banned') fatalError = e.message;
    } catch (e) {
      if (!silent && boot == null) fatalError = 'Could not start: $e';
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------ settings
  void setRegion(String code) {
    storage.region = code;
    notifyListeners();
    if (status == ConnStatus.connected) unawaited(reconnect());
  }

  void setProtocol(String p) {
    storage.protocol = p;
    notifyListeners();
    if (status == ConnStatus.connected) unawaited(reconnect());
  }

  void setAutoReconnect(bool v) {
    storage.autoReconnect = v;
    notifyListeners();
  }

  void setAutoConnect(bool v) {
    storage.autoConnectOnLaunch = v;
    notifyListeners();
  }

  void clearMessage() {
    message = null;
    blockingCode = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ connect
  Future<void> toggle() async {
    if (status == ConnStatus.connected || status == ConnStatus.connecting || status == ConnStatus.reconnecting) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> reconnect() async {
    _failedNodes.clear();
    await connect(isReconnect: true);
  }

  Future<void> connect({bool isReconnect = false}) async {
    if (_busy) return;
    _busy = true;
    _userWantsConnection = true;
    message = null;
    blockingCode = null;
    status = isReconnect ? ConnStatus.reconnecting : ConnStatus.connecting;
    notifyListeners();

    try {
      // Tear down any existing tunnel first so API calls don't go through a dead server.
      if (engine.state != EngineState.disconnected || engine.activeProtocol != null) {
        await engine.stop();
      }
      if (!await engine.requestPermission()) {
        throw ApiException('permission', 'VPN permission is required to connect.');
      }
      final order = _protocolOrder();
      if (order.isEmpty) throw ApiException('no_protocol', 'No protocol available.');

      ApiException? lastError;
      for (final proto in order) {
        // up to two different servers per protocol
        for (var attempt = 0; attempt < 2; attempt++) {
          if (!_userWantsConnection) return;
          try {
            final ok = await _tryOnce(proto);
            if (!_userWantsConnection) {
              await engine.stop();
              return;
            }
            if (ok) {
              _onConnected();
              return;
            }
          } on ApiException catch (e) {
            lastError = e;
            const fatal = {'quota_exceeded', 'pro_required', 'banned', 'device_revoked', 'maintenance', 'protocol_unavailable'};
            if (fatal.contains(e.code)) rethrow;
            if (e.code == 'no_capacity') break; // try next protocol
          }
        }
      }
      throw lastError ?? ApiException('connect_failed', 'Could not establish a connection. Try another location.');
    } on ApiException catch (e) {
      await engine.stop();
      _userWantsConnection = false;
      status = ConnStatus.disconnected;
      session = null;
      connectedAt = null;
      message = e.message;
      if (e.code == 'quota_exceeded' || e.code == 'pro_required') blockingCode = e.code;
      if (e.code == 'device_revoked') unawaited(refresh());
    } catch (e) {
      await engine.stop();
      _userWantsConnection = false;
      status = ConnStatus.disconnected;
      message = 'Connection failed: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  List<String> _protocolOrder() {
    final b = boot;
    final allowed = b?.allowedProtocols ?? const ['wireguard', 'vless'];
    if (protocol != 'auto') return allowed.contains(protocol) ? [protocol] : <String>[];
    final order = b?.fallbackOrder ?? const ['wireguard', 'vless'];
    return order.where(allowed.contains).toList();
  }

  /// One attempt: get a config (server or cache), start the tunnel, verify traffic.
  Future<bool> _tryOnce(String proto) async {
    final keys = proto == 'wireguard' ? await storage.wireguardKeys() : null;
    Map<String, dynamic> raw;
    try {
      raw = await api.connect(
        installId: storage.installId,
        region: region,
        protocol: proto,
        wgPublicKey: keys?.publicKey,
        excludeNodes: _failedNodes.toList(),
      );
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      // API blocked/unreachable: fall back to the last working config.
      final cached = storage.cachedSession(proto);
      if (cached == null) rethrow;
      if (_failedNodes.contains(SessionConfig.fromJson(cached).nodeId)) rethrow;
      raw = cached;
    }
    final cfg = SessionConfig.fromJson(raw);
    session = cfg;
    notifyListeners();

    if (cfg.protocol == 'wireguard') {
      await engine.startWireGuard(wgQuick: cfg.wgQuick(keys!.privateKey), endpoint: cfg.endpoint);
    } else {
      await engine.startVless(link: cfg.vlessLink!, dns: cfg.dns);
    }

    final up = await engine.waitConnected(const Duration(seconds: 15));
    if (up) {
      // give routes a moment, then verify real traffic
      await Future<void>.delayed(const Duration(milliseconds: 600));
      if (await engine.healthCheck() || await engine.healthCheck()) {
        storage.cacheSession(cfg.protocol, raw);
        return true;
      }
    }
    _failedNodes.add(cfg.nodeId);
    await engine.stop();
    return false;
  }

  void _onConnected() {
    status = ConnStatus.connected;
    connectedAt ??= DateTime.now();
    _reconnectAttempts = 0;
    _healthFailures = 0;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    _health?.cancel();
    _health = Timer.periodic(const Duration(seconds: 45), (_) => _periodicHealth());
    _refresh?.cancel();
    _refresh = Timer.periodic(const Duration(minutes: 10), (_) => refresh());
    storage.connectCount = storage.connectCount + 1;
    if (showAds && (boot?.ads.interstitial ?? false) &&
        storage.connectCount % (boot?.ads.interstitialEvery ?? 2) == 0) {
      ads.showInterstitial();
    }
    unawaited(refresh());
  }

  Future<void> _periodicHealth() async {
    if (status != ConnStatus.connected || _busy) return;
    final ok = await engine.healthCheck();
    if (ok) {
      _healthFailures = 0;
      return;
    }
    _healthFailures++;
    if (_healthFailures >= 2 && autoReconnect) {
      // Node blocked, quota reached or server gone → fail over.
      if (session != null) _failedNodes.add(session!.nodeId);
      connectedAt = null;
      await connect(isReconnect: true);
    }
  }

  void _onEngineState(EngineState s) {
    if (s == EngineState.disconnected && status == ConnStatus.connected && _userWantsConnection && !_busy) {
      // Tunnel dropped unexpectedly (network change, server restart...).
      if (autoReconnect && _reconnectAttempts < 5) {
        _reconnectAttempts++;
        status = ConnStatus.reconnecting;
        notifyListeners();
        final delay = Duration(seconds: 2 * _reconnectAttempts);
        Future.delayed(delay, () {
          if (_userWantsConnection && !_busy) connect(isReconnect: true);
        });
      } else {
        _stopTimers();
        status = ConnStatus.disconnected;
        connectedAt = null;
        message = 'Connection lost.';
        notifyListeners();
      }
    }
  }

  Future<void> disconnect() async {
    _userWantsConnection = false;
    status = ConnStatus.disconnecting;
    notifyListeners();
    _stopTimers();
    await engine.stop();
    unawaited(api.disconnect(storage.installId));
    status = ConnStatus.disconnected;
    connectedAt = null;
    session = null;
    _failedNodes.clear();
    notifyListeners();
    if (showAds) ads.preloadInterstitial();
  }

  void _stopTimers() {
    _ticker?.cancel();
    _health?.cancel();
    _refresh?.cancel();
  }

  /// Called by the account screen after sign-in / sign-out.
  Future<void> onAccountChanged() async {
    if (status != ConnStatus.disconnected) await disconnect();
    storage.clearSessions();
    boot = null;
    await refresh(silent: false);
  }

  @override
  void dispose() {
    _stopTimers();
    _engineSub?.cancel();
    super.dispose();
  }
}
