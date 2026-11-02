import 'package:flutter_test/flutter_test.dart';
import 'package:ypn_vpn/models/models.dart';

void main() {
  test('wg-quick config is built from server response', () {
    final cfg = SessionConfig.fromJson({
      'protocol': 'wireguard',
      'node': {'id': 'n1', 'name': 'sg-1', 'region': 'sg'},
      'wireguard': {
        'address': '10.66.0.2/32',
        'dns': ['1.1.1.1'],
        'mtu': 1280,
        'server_public_key': 'PUB=',
        'endpoint': '1.2.3.4:51820',
        'allowed_ips': '0.0.0.0/0, ::/0',
        'keepalive': 25,
      },
    });
    final conf = cfg.wgQuick('PRIV=');
    expect(conf, contains('PrivateKey = PRIV='));
    expect(conf, contains('Endpoint = 1.2.3.4:51820'));
    expect(cfg.endpoint, '1.2.3.4:51820');
  });

  test('bootstrap parses plan and regions', () {
    final b = Bootstrap.fromJson({
      'user': {'id': 'u', 'is_anonymous': true},
      'plan': {'name': 'free', 'daily_limit_bytes': 1000, 'used_today_bytes': 500, 'max_devices': 1},
      'ads': {'enabled': true},
      'protocols': {'allowed': ['wireguard'], 'fallback_order': ['wireguard']},
      'regions': [
        {'code': 'sg', 'name': 'Singapore', 'country_code': 'SG', 'available': true, 'load': 10}
      ],
      'app': {},
      'products': {'monthly': 'ypn_pro_monthly'},
    });
    expect(b.plan.usageFraction, 0.5);
    expect(b.regions.single.flag, '🇸🇬');
    expect(b.ads.banner, isTrue);
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
  });
}
