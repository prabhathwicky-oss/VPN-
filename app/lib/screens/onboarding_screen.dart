import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../main.dart';
import '../services/storage.dart';
import '../theme.dart';

/// First-launch disclosure required by Google Play's VPN policy:
/// explains what the VpnService does and what data is (not) collected.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Palette.mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.shield_rounded, color: Palette.mint, size: 36),
            ),
            const SizedBox(height: 24),
            Text('Welcome to ${Env.appName}', style: t.headlineMedium),
            const SizedBox(height: 8),
            Text('Private, fast and built to work on restricted networks.', style: t.bodySmall?.copyWith(fontSize: 15)),
            const SizedBox(height: 28),
            const _Point(
              icon: Icons.vpn_lock_rounded,
              title: 'Uses Android VpnService',
              body: 'When you connect, your device traffic is routed through an encrypted tunnel to our servers. '
                  'Android will ask for your permission the first time.',
            ),
            const _Point(
              icon: Icons.visibility_off_rounded,
              title: 'No activity logs',
              body: 'We never record the websites you visit, your DNS queries or the content of your traffic.',
            ),
            const _Point(
              icon: Icons.data_usage_rounded,
              title: 'What we do keep',
              body: 'An anonymous account ID, your plan, which server you are assigned to, and total data used per day '
                  '(to apply free-plan limits). Free plan shows ads via Google AdMob.',
            ),
            const Spacer(),
            Center(
              child: TextButton(
                onPressed: () => launchUrl(Uri.parse(Env.privacyUrl), mode: LaunchMode.externalApplication),
                child: const Text('Read the full Privacy Policy'),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                context.read<Storage>().onboarded = true;
                Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const RootGate()));
              },
              child: const Text('Agree & continue'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: Palette.mint, size: 22),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleMedium),
            const SizedBox(height: 4),
            Text(body, style: t.bodySmall?.copyWith(height: 1.4)),
          ]),
        ),
      ]),
    );
  }
}
