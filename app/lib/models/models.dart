// Plain data models parsed from the edge-function JSON.

int _int(dynamic v, [int d = 0]) => v is num ? v.toInt() : int.tryParse('$v') ?? d;

class Region {
  final String code;
  final String name;
  final String countryCode;
  final bool proOnly;
  final bool locked;
  final bool available;
  final int load;
  final bool stealth;

  Region({
    required this.code,
    required this.name,
    required this.countryCode,
    required this.proOnly,
    required this.locked,
    required this.available,
    required this.load,
    required this.stealth,
  });

  factory Region.fromJson(Map<String, dynamic> j) => Region(
        code: j['code'] as String,
        name: j['name'] as String? ?? j['code'] as String,
        countryCode: j['country_code'] as String? ?? '',
        proOnly: j['pro_only'] == true,
        locked: j['locked'] == true,
        available: j['available'] == true,
        load: _int(j['load'], 100),
        stealth: j['stealth'] == true,
      );

  String get flag => countryFlag(countryCode);
}

String countryFlag(String cc) {
  if (cc.length != 2) return '🌐';
  final up = cc.toUpperCase();
  return String.fromCharCodes(up.codeUnits.map((c) => c + 127397));
}

class PlanInfo {
  final String name; // free | pro
  final DateTime? expiresAt;
  final int? dailyLimitBytes;
  final int usedTodayBytes;
  final int? speedLimitMbps;
  final int maxDevices;

  PlanInfo({
    required this.name,
    this.expiresAt,
    this.dailyLimitBytes,
    required this.usedTodayBytes,
    this.speedLimitMbps,
    required this.maxDevices,
  });

  bool get isPro => name == 'pro';

  double get usageFraction {
    final lim = dailyLimitBytes;
    if (lim == null || lim <= 0) return 0;
    return (usedTodayBytes / lim).clamp(0.0, 1.0);
  }

  factory PlanInfo.fromJson(Map<String, dynamic> j) => PlanInfo(
        name: j['name'] as String? ?? 'free',
        expiresAt: j['expires_at'] == null ? null : DateTime.tryParse('${j['expires_at']}'),
        dailyLimitBytes: j['daily_limit_bytes'] == null ? null : _int(j['daily_limit_bytes']),
        usedTodayBytes: _int(j['used_today_bytes']),
        speedLimitMbps: j['speed_limit_mbps'] == null ? null : _int(j['speed_limit_mbps']),
        maxDevices: _int(j['max_devices'], 1),
      );
}

class AdsConfig {
  final bool enabled;
  final bool banner;
  final bool interstitial;
  final int interstitialEvery;

  AdsConfig({required this.enabled, required this.banner, required this.interstitial, required this.interstitialEvery});

  factory AdsConfig.fromJson(Map<String, dynamic>? j) {
    j ??= const {};
    final enabled = j['enabled'] == true;
    return AdsConfig(
      enabled: enabled,
      banner: enabled && j['banner'] != false,
      interstitial: enabled && j['interstitial'] != false,
      interstitialEvery: _int(j['interstitial_every'], 2).clamp(1, 100),
    );
  }
}

class Bootstrap {
  final String userId;
  final bool isAnonymous;
  final String? email;
  final PlanInfo plan;
  final AdsConfig ads;
  final List<String> allowedProtocols;
  final List<String> fallbackOrder;
  final List<Region> regions;
  final String? announcement;
  final String minVersion;
  final Map<String, String> products;

  Bootstrap({
    required this.userId,
    required this.isAnonymous,
    required this.email,
    required this.plan,
    required this.ads,
    required this.allowedProtocols,
    required this.fallbackOrder,
    required this.regions,
    required this.announcement,
    required this.minVersion,
    required this.products,
  });

  factory Bootstrap.fromJson(Map<String, dynamic> j) {
    final user = (j['user'] as Map?)?.cast<String, dynamic>() ?? {};
    final protocols = (j['protocols'] as Map?)?.cast<String, dynamic>() ?? {};
    final app = (j['app'] as Map?)?.cast<String, dynamic>() ?? {};
    final products = (j['products'] as Map?)?.cast<String, dynamic>() ?? {};
    return Bootstrap(
      userId: user['id'] as String? ?? '',
      isAnonymous: user['is_anonymous'] == true,
      email: user['email'] as String?,
      plan: PlanInfo.fromJson((j['plan'] as Map?)?.cast<String, dynamic>() ?? {}),
      ads: AdsConfig.fromJson((j['ads'] as Map?)?.cast<String, dynamic>()),
      allowedProtocols: ((protocols['allowed'] as List?) ?? const ['wireguard', 'vless']).cast<String>(),
      fallbackOrder: ((protocols['fallback_order'] as List?) ?? const ['wireguard', 'vless']).cast<String>(),
      regions: ((j['regions'] as List?) ?? const [])
          .map((e) => Region.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      announcement: app['announcement'] as String?,
      minVersion: app['min_version'] as String? ?? '1.0.0',
      products: products.map((k, v) => MapEntry(k, '$v')),
    );
  }
}

/// Result of /vpn-connect
class SessionConfig {
  final String protocol; // wireguard | vless
  final String nodeId;
  final String nodeName;
  final String regionCode;
  final Map<String, dynamic>? wireguard;
  final String? vlessLink;
  final List<String> dns;

  SessionConfig({
    required this.protocol,
    required this.nodeId,
    required this.nodeName,
    required this.regionCode,
    this.wireguard,
    this.vlessLink,
    required this.dns,
  });

  factory SessionConfig.fromJson(Map<String, dynamic> j) {
    final node = (j['node'] as Map?)?.cast<String, dynamic>() ?? {};
    final wg = (j['wireguard'] as Map?)?.cast<String, dynamic>();
    final vl = (j['vless'] as Map?)?.cast<String, dynamic>();
    final dns = ((wg?['dns'] ?? vl?['dns']) as List?)?.map((e) => '$e').toList() ?? ['1.1.1.1'];
    return SessionConfig(
      protocol: j['protocol'] as String,
      nodeId: node['id'] as String? ?? '',
      nodeName: node['name'] as String? ?? '',
      regionCode: node['region'] as String? ?? '',
      wireguard: wg,
      vlessLink: vl?['link'] as String?,
      dns: dns,
    );
  }

  /// wg-quick configuration for the WireGuard engine.
  String wgQuick(String privateKey) {
    final w = wireguard!;
    return '[Interface]\n'
        'PrivateKey = $privateKey\n'
        'Address = ${w['address']}\n'
        'DNS = ${dns.join(', ')}\n'
        'MTU = ${w['mtu'] ?? 1280}\n'
        '\n'
        '[Peer]\n'
        'PublicKey = ${w['server_public_key']}\n'
        'AllowedIPs = ${w['allowed_ips'] ?? '0.0.0.0/0, ::/0'}\n'
        'Endpoint = ${w['endpoint']}\n'
        'PersistentKeepalive = ${w['keepalive'] ?? 25}\n';
  }

  String get endpoint => (wireguard?['endpoint'] as String?) ?? '';
}

class ApiException implements Exception {
  final String code;
  final String message;
  final int status;
  ApiException(this.code, this.message, [this.status = 0]);

  bool get isNetwork => code == 'network';
  @override
  String toString() => message;
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  double v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}

String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
