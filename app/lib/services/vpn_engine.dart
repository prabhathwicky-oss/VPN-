import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray_client/flutter_v2ray.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';

import '../config/env.dart';

enum EngineState { disconnected, connecting, connected }

/// Wraps the two tunnel implementations behind one interface:
///  - WireGuard  (standard nodes, fastest)
///  - Xray VLESS + REALITY (stealth nodes, for restricted networks)
class VpnEngine {
  final _wg = WireGuardFlutter.instance;
  late final V2ray _v2 = V2ray(onStatusChanged: _onV2Status);

  final _states = StreamController<EngineState>.broadcast();
  Stream<EngineState> get states => _states.stream;

  EngineState _state = EngineState.disconnected;
  EngineState get state => _state;

  String? _active; // 'wireguard' | 'vless'
  String? get activeProtocol => _active;

  int uploadSpeed = 0; // bytes/s (stealth only)
  int downloadSpeed = 0;
  int sessionUpload = 0;
  int sessionDownload = 0;

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _wg.initialize(interfaceName: 'wg0');
      _wg.vpnStageSnapshot.listen(_onWgStage);
    } catch (e) {
      debugPrint('wireguard init failed: $e');
    }
    try {
      await _v2.initialize(
        notificationIconResourceType: 'mipmap',
        notificationIconResourceName: 'ic_launcher',
      );
    } catch (e) {
      debugPrint('v2ray init failed: $e');
    }
    _ready = true;
  }

  /// Android VPN consent dialog (shared by both engines).
  Future<bool> requestPermission() async {
    try {
      return await _v2.requestPermission();
    } catch (_) {
      return true;
    }
  }

  void _set(EngineState s) {
    if (_state == s) return;
    _state = s;
    _states.add(s);
  }

  void _onWgStage(dynamic stage) {
    if (_active != 'wireguard') return;
    final name = '$stage'.split('.').last.toLowerCase();
    switch (name) {
      case 'connected':
        _set(EngineState.connected);
        break;
      case 'connecting':
      case 'preparing':
      case 'authenticating':
      case 'reconnect':
      case 'waitingconnection':
        _set(EngineState.connecting);
        break;
      case 'disconnected':
      case 'nointernet':
      case 'noconnection':
      case 'denied':
      case 'exiting':
        _set(EngineState.disconnected);
        break;
      default:
        break;
    }
  }

  void _onV2Status(V2RayStatus s) {
    if (_active != 'vless') return;
    uploadSpeed = s.uploadSpeed;
    downloadSpeed = s.downloadSpeed;
    sessionUpload = s.upload;
    sessionDownload = s.download;
    switch (s.state.toUpperCase()) {
      case 'CONNECTED':
        _set(EngineState.connected);
        break;
      case 'CONNECTING':
        _set(EngineState.connecting);
        break;
      default:
        _set(EngineState.disconnected);
    }
  }

  Future<void> startWireGuard({required String wgQuick, required String endpoint}) async {
    await stop();
    _active = 'wireguard';
    _set(EngineState.connecting);
    await _wg.startVpn(
      serverAddress: endpoint,
      wgQuickConfig: wgQuick,
      providerBundleIdentifier: Env.androidPackage,
    );
  }

  Future<void> startVless({required String link, required List<String> dns}) async {
    await stop();
    _active = 'vless';
    _set(EngineState.connecting);
    final parser = V2ray.parseFromURL(link);
    parser.dns = {'servers': dns};
    await _v2.startV2Ray(
      remark: parser.remark,
      config: parser.getFullConfiguration(),
      blockedApps: null,
      bypassSubnets: null,
      proxyOnly: false,
    );
  }

  Future<void> stop() async {
    final was = _active;
    _active = null;
    try {
      if (was == 'wireguard') await _wg.stopVpn();
      if (was == 'vless') await _v2.stopV2Ray();
    } catch (e) {
      debugPrint('stop failed: $e');
    }
    uploadSpeed = downloadSpeed = sessionUpload = sessionDownload = 0;
    _set(EngineState.disconnected);
  }

  /// Wait until the tunnel reports connected (or time out).
  Future<bool> waitConnected(Duration timeout) async {
    if (_state == EngineState.connected) return true;
    try {
      await states.firstWhere((s) => s == EngineState.connected).timeout(timeout);
      return true;
    } catch (_) {
      return _state == EngineState.connected;
    }
  }

  /// Verify traffic actually flows through the tunnel.
  Future<bool> healthCheck() async {
    if (_active == 'vless') {
      try {
        final ms = await _v2.getConnectedServerDelay(url: 'https://www.gstatic.com/generate_204');
        return ms > 0;
      } catch (_) {
        return false;
      }
    }
    if (_active == 'wireguard') {
      for (final url in const ['https://www.gstatic.com/generate_204', 'https://cp.cloudflare.com/generate_204']) {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
        try {
          final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 7));
          final res = await req.close().timeout(const Duration(seconds: 7));
          await res.drain<void>();
          if (res.statusCode == 204 || res.statusCode == 200) return true;
        } catch (_) {
          // try next
        } finally {
          client.close(force: true);
        }
      }
      return false;
    }
    return false;
  }
}
