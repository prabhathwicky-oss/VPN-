import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../services/storage.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'plans_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final boot = app.boot;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section('Connection'),
          Card(
            child: Column(children: [
              SwitchListTile(
                title: const Text('Auto-reconnect'),
                subtitle: const Text('Reconnect or switch server if the tunnel drops'),
                value: app.autoReconnect,
                onChanged: app.setAutoReconnect,
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Connect on app launch'),
                value: app.storage.autoConnectOnLaunch,
                onChanged: app.setAutoConnect,
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Protocol'),
                subtitle: Text(switch (app.protocol) {
                  'wireguard' => 'Fast (WireGuard)',
                  'vless' => 'Stealth (VLESS + REALITY)',
                  _ => 'Auto — WireGuard, falls back to Stealth',
                }),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pickProtocol(context, app),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Kill switch'),
                subtitle: const Text('Block internet when the VPN is off — set in Android settings'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _killSwitchHelp(context),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _Section('Account'),
          Card(
            child: Column(children: [
              ListTile(
                title: Text(boot?.email ?? 'Anonymous account'),
                subtitle: Text(boot == null ? '' : 'ID ${boot.userId.length >= 8 ? boot.userId.substring(0, 8) : boot.userId} • ${boot.plan.isPro ? 'Pro' : 'Free'} plan'),
                trailing: boot?.plan.isPro == true
                    ? const Icon(Icons.bolt_rounded, color: Palette.violet)
                    : TextButton(
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlansScreen())),
                        child: const Text('Upgrade'),
                      ),
              ),
              const Divider(height: 1),
              if (boot?.isAnonymous ?? true)
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Save account with email'),
                  subtitle: const Text('Keep your Pro plan if you reinstall or change phone'),
                  onTap: () => _emailFlow(context, link: true),
                ),
              ListTile(
                leading: const Icon(Icons.login_rounded),
                title: const Text('Sign in to another account'),
                onTap: () => _emailFlow(context, link: false),
              ),
              if (!(boot?.isAnonymous ?? true))
                ListTile(
                  leading: const Icon(Icons.logout_rounded),
                  title: const Text('Sign out'),
                  onTap: () async {
                    await context.read<Api>().signOut();
                    await context.read<Storage>().resetIdentity();
                    await app.onAccountChanged();
                  },
                ),
            ]),
          ),
          if (boot != null) ...[
            const SizedBox(height: 20),
            _Section('Usage'),
            Card(
              child: ListTile(
                title: Text('Today: ${formatBytes(boot.plan.usedTodayBytes)}'),
                subtitle: Text(boot.plan.isPro
                    ? 'Unlimited data on Pro'
                    : 'Free limit ${formatBytes(boot.plan.dailyLimitBytes ?? 0)} per day • resets 00:00 UTC'),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _Section('About'),
          Card(
            child: Column(children: [
              ListTile(
                title: const Text('Privacy policy'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => launchUrl(Uri.parse(Env.privacyUrl), mode: LaunchMode.externalApplication),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Terms of service'),
                trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                onTap: () => launchUrl(Uri.parse(Env.termsUrl), mode: LaunchMode.externalApplication),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Contact support'),
                subtitle: const Text(Env.supportEmail),
                onTap: () => launchUrl(Uri.parse('mailto:${Env.supportEmail}')),
              ),
              const Divider(height: 1),
              ListTile(title: const Text('Version'), trailing: Text(Env.appVersion, style: t.bodySmall)),
            ]),
          ),
        ],
      ),
    );
  }

  void _pickProtocol(BuildContext context, AppState app) {
    final allowed = app.boot?.allowedProtocols ?? const ['wireguard', 'vless'];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Palette.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final o in const [
            ('auto', 'Auto (recommended)', 'Tries WireGuard first, switches to Stealth if blocked'),
            ('wireguard', 'Fast — WireGuard', 'Best speed and battery life'),
            ('vless', 'Stealth — VLESS + REALITY', 'Looks like normal HTTPS; works where VPNs are blocked'),
          ])
            ListTile(
              enabled: o.$1 == 'auto' || allowed.contains(o.$1),
              title: Text(o.$2),
              subtitle: Text(o.$3),
              trailing: app.protocol == o.$1 ? const Icon(Icons.check_rounded, color: Palette.mint) : null,
              onTap: () {
                app.setProtocol(o.$1);
                Navigator.pop(ctx);
              },
            ),
        ]),
      ),
    );
  }

  void _killSwitchHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn on the kill switch'),
        content: const Text(
          '1. Open Android Settings › Network & internet › VPN\n'
          '2. Tap the gear next to ${Env.appName}\n'
          '3. Turn on “Always-on VPN” and “Block connections without VPN”\n\n'
          'Android will then block all traffic whenever the tunnel is down.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
      ),
    );
  }

  Future<void> _emailFlow(BuildContext context, {required bool link}) async {
    final api = context.read<Api>();
    final app = context.read<AppState>();
    final emailCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    var sent = false;
    var busy = false;
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(link ? 'Save account with email' : 'Sign in with email'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: emailCtrl,
              enabled: !sent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'you@example.com'),
            ),
            if (sent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '6-digit code from your email'),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 10),
              Text(error!, style: const TextStyle(color: Palette.coral)),
            ],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
              onPressed: busy
                  ? null
                  : () async {
                      setS(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        final email = emailCtrl.text.trim();
                        if (!sent) {
                          await api.sendEmailCode(email, link: link);
                          setS(() => sent = true);
                        } else {
                          await api.verifyEmailCode(email, codeCtrl.text.trim(), link: link);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!link) {
                            await context.read<Storage>().resetIdentity();
                            await app.onAccountChanged();
                          } else {
                            await app.refresh();
                          }
                        }
                      } catch (e) {
                        setS(() => error = '$e');
                      } finally {
                        if (ctx.mounted) setS(() => busy = false);
                      }
                    },
              child: Text(sent ? 'Verify' : 'Send code'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(label.toUpperCase(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w700)),
      );
}
