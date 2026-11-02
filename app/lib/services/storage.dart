import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence: install id, WireGuard keys, user settings, cached
/// session configs (used when the API is unreachable, e.g. under censorship).
class Storage {
  Storage._(this._p);
  final SharedPreferences _p;

  static Future<Storage> open() async => Storage._(await SharedPreferences.getInstance());

  String get installId {
    var id = _p.getString('install_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      _p.setString('install_id', id);
    }
    return id;
  }

  bool get onboarded => _p.getBool('onboarded') ?? false;
  set onboarded(bool v) => _p.setBool('onboarded', v);

  String get region => _p.getString('region') ?? 'auto';
  set region(String v) => _p.setString('region', v);

  String get protocol => _p.getString('protocol') ?? 'auto';
  set protocol(String v) => _p.setString('protocol', v);

  bool get autoReconnect => _p.getBool('auto_reconnect') ?? true;
  set autoReconnect(bool v) => _p.setBool('auto_reconnect', v);

  bool get autoConnectOnLaunch => _p.getBool('auto_connect') ?? false;
  set autoConnectOnLaunch(bool v) => _p.setBool('auto_connect', v);

  int get connectCount => _p.getInt('connect_count') ?? 0;
  set connectCount(int v) => _p.setInt('connect_count', v);

  /// Last successful /vpn-connect response per protocol.
  Map<String, dynamic>? cachedSession(String protocol) {
    final s = _p.getString('cache_$protocol');
    if (s == null) return null;
    try {
      return (jsonDecode(s) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  void cacheSession(String protocol, Map<String, dynamic> json) =>
      _p.setString('cache_$protocol', jsonEncode(json));

  void clearSessions() {
    _p.remove('cache_wireguard');
    _p.remove('cache_vless');
  }

  /// Device WireGuard key pair. The private key never leaves the phone.
  Future<({String privateKey, String publicKey})> wireguardKeys() async {
    final priv = _p.getString('wg_priv');
    final pub = _p.getString('wg_pub');
    if (priv != null && pub != null) return (privateKey: priv, publicKey: pub);
    final kp = await X25519().newKeyPair();
    final privBytes = await kp.extractPrivateKeyBytes();
    final pubKey = await kp.extractPublicKey();
    final p1 = base64Encode(privBytes);
    final p2 = base64Encode(pubKey.bytes);
    await _p.setString('wg_priv', p1);
    await _p.setString('wg_pub', p2);
    return (privateKey: p1, publicKey: p2);
  }

  Future<void> resetIdentity() async {
    await _p.remove('wg_priv');
    await _p.remove('wg_pub');
    clearSessions();
  }
}
