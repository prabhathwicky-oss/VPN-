import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/ads_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/connect_button.dart';
import 'plans_screen.dart';
import 'servers_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) context.read<AppState>().refresh();
  }

  void _openPlans() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlansScreen()));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final boot = app.boot;
    final t = Theme.of(context).textTheme;

    // Paywall prompt for quota / Pro-only errors
    if (app.blockingCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final code = app.blockingCode;
        if (code == null || !mounted) return;
        app.clearMessage();
        _showUpgradeSheet(code == 'quota_exceeded'
            ? 'You\'ve used today\'s free data'
            : 'This location is Pro only');
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.shield_rounded, color: Palette.mint, size: 26),
          const SizedBox(width: 8),
          const Text('YPN', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(width: 8),
          if (app.isPro) const _ProBadge(),
        ]),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => app.refresh(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              if (boot?.announcement != null) _Announcement(text: boot!.announcement!),
              if (app.message != null) _MessageBar(text: app.message!, onClose: app.clearMessage),
              const SizedBox(height: 12),
              Center(child: ConnectButton(status: app.status, onTap: app.toggle)),
              const SizedBox(height: 4),
              Center(child: Text(_statusLabel(app), style: t.titleLarge?.copyWith(color: _statusColor(app.status)))),
              const SizedBox(height: 6),
              Center(child: Text(_subLabel(app), style: t.bodySmall?.copyWith(fontSize: 14))),
              const SizedBox(height: 26),
              _LocationCard(app: app),
              const SizedBox(height: 12),
              _ProtocolSelector(app: app),
              const SizedBox(height: 12),
              if (boot != null) _UsageCard(plan: boot.plan, app: app, onUpgrade: _openPlans),
              const SizedBox(height: 12),
              if (!app.isPro)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Palette.violet, foregroundColor: Colors.white),
                  onPressed: _openPlans,
                  icon: const Icon(Icons.bolt_rounded),
                  label: const Text('Go Pro — all locations, no ads'),
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: app.showAds && (boot?.ads.banner ?? false)
          ? const SafeArea(child: SizedBox(height: 50, child: Center(child: BannerAdSlot())))
          : null,
    );
  }

  void _showUpgradeSheet(String title) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.bolt_rounded, color: Palette.violet, size: 48),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(ctx).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Upgrade to Pro for unlimited data, every location, faster servers and no ads.',
              textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall?.copyWith(fontSize: 14)),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.violet, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _openPlans();
            },
            child: const Text('See Pro plans'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Not now')),
        ]),
      ),
    );
  }

  String _statusLabel(AppState app) => switch (app.status) {
        ConnStatus.connected => 'Protected',
        ConnStatus.connecting => 'Connecting…',
        ConnStatus.reconnecting => 'Reconnecting…',
        ConnStatus.disconnecting => 'Disconnecting…',
        ConnStatus.disconnected => 'Not protected',
      };

  String _subLabel(AppState app) {
    final s = app.session;
    if (app.status == ConnStatus.connected && s != null) {
      final proto = s.protocol == 'vless' ? 'Stealth' : 'WireGuard';
      return '${formatDuration(app.elapsed)}  •  $proto  •  ${s.regionCode.toUpperCase()}';
    }
    if (app.status == ConnStatus.disconnected) return 'Tap to connect';
    if (s != null) return s.protocol == 'vless' ? 'Trying stealth mode…' : 'Trying WireGuard…';
    return 'Finding the best server…';
  }

  Color _statusColor(ConnStatus s) => switch (s) {
        ConnStatus.connected => Palette.mint,
        ConnStatus.disconnected => Palette.text,
        _ => Palette.amber,
      };
}

class _ProBadge extends StatelessWidget {
  const _ProBadge();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: Palette.violet, borderRadius: BorderRadius.circular(8)),
        child: const Text('PRO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
      );
}

class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final r = app.selectedRegion;
    final t = Theme.of(context).textTheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ServersScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Palette.surfaceHigh, borderRadius: BorderRadius.circular(12)),
              child: r == null
                  ? const Icon(Icons.bolt_rounded, color: Palette.mint)
                  : Text(r.flag, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Location', style: t.bodySmall),
                const SizedBox(height: 2),
                Text(r?.name ?? 'Fastest server', style: t.titleMedium),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Palette.muted),
          ]),
        ),
      ),
    );
  }
}

class _ProtocolSelector extends StatelessWidget {
  const _ProtocolSelector({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final allowed = app.boot?.allowedProtocols ?? const ['wireguard', 'vless'];
    final options = <(String, String, IconData)>[
      ('auto', 'Auto', Icons.auto_awesome_rounded),
      ('wireguard', 'Fast', Icons.speed_rounded),
      ('vless', 'Stealth', Icons.visibility_off_rounded),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            for (final o in options)
              Expanded(
                child: _Seg(
                  label: o.$2,
                  icon: o.$3,
                  selected: app.protocol == o.$1,
                  enabled: o.$1 == 'auto' || allowed.contains(o.$1),
                  onTap: () => app.setProtocol(o.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.label, required this.icon, required this.selected, required this.enabled, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = !enabled ? Palette.line : (selected ? Palette.ink : Palette.muted);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Palette.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.plan, required this.app, required this.onUpgrade});
  final PlanInfo plan;
  final AppState app;
  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final speed = app.engine.activeProtocol == 'vless' && app.status == ConnStatus.connected
        ? '↓ ${formatBytes(app.engine.downloadSpeed)}/s   ↑ ${formatBytes(app.engine.uploadSpeed)}/s'
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('Data today', style: t.bodySmall),
            const Spacer(),
            Text(
              plan.isPro
                  ? '${formatBytes(plan.usedTodayBytes)} • Unlimited'
                  : '${formatBytes(plan.usedTodayBytes)} of ${formatBytes(plan.dailyLimitBytes ?? 0)}',
              style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ]),
          if (!plan.isPro) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: plan.usageFraction,
                minHeight: 8,
                backgroundColor: Palette.surfaceHigh,
                color: plan.usageFraction > 0.85 ? Palette.coral : Palette.mint,
              ),
            ),
            if (plan.speedLimitMbps != null) ...[
              const SizedBox(height: 8),
              Text('Free plan speed up to ${plan.speedLimitMbps} Mbps', style: t.bodySmall),
            ],
          ],
          if (speed != null) ...[
            const SizedBox(height: 10),
            Text(speed, style: t.bodySmall?.copyWith(color: Palette.text)),
          ],
        ]),
      ),
    );
  }
}

class _Announcement extends StatelessWidget {
  const _Announcement({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Palette.violet.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.violet.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.campaign_rounded, color: Palette.violet),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

class _MessageBar extends StatelessWidget {
  const _MessageBar({required this.text, required this.onClose});
  final String text;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: Palette.coral.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.coral.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, color: Palette.coral, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
          IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: onClose),
        ]),
      );
}
