import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';

import '../services/billing_service.dart';
import '../state/app_state.dart';
import '../theme.dart';

class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final billing = context.watch<BillingService>();
    final t = Theme.of(context).textTheme;
    final plan = app.boot?.plan;
    final products = app.boot?.products ?? const <String, String>{};

    return Scaffold(
      appBar: AppBar(title: const Text('YPN Pro')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.bolt_rounded, color: Palette.violet, size: 56),
          const SizedBox(height: 8),
          Text(app.isPro ? 'You\'re on Pro' : 'Unlock everything',
              textAlign: TextAlign.center, style: t.headlineMedium),
          if (app.isPro && plan?.expiresAt != null) ...[
            const SizedBox(height: 6),
            Text('Renews / expires ${_date(plan!.expiresAt!)}', textAlign: TextAlign.center, style: t.bodySmall),
          ],
          const SizedBox(height: 24),
          const _Compare(),
          const SizedBox(height: 24),
          if (!billing.available)
            const _Note(text: 'Google Play billing is not available on this device.')
          else if (billing.products.isEmpty)
            const _Note(text: 'Plans are loading or not yet published in Play Console.')
          else
            for (final p in billing.products) ...[
              _ProductCard(
                product: p,
                highlight: p.id == products['yearly'],
                busy: billing.busy,
                onBuy: () => billing.buy(p, app.boot?.userId ?? ''),
              ),
              const SizedBox(height: 12),
            ],
          if (billing.message != null) ...[
            const SizedBox(height: 4),
            Text(billing.message!, textAlign: TextAlign.center, style: t.bodyMedium),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: billing.busy ? null : billing.restore,
            child: const Text('Restore purchases'),
          ),
          const SizedBox(height: 8),
          Text(
            'Subscriptions renew automatically until cancelled in Google Play. '
            'Cancel any time from Play Store › Payments & subscriptions.',
            textAlign: TextAlign.center,
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }

  String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class _Compare extends StatelessWidget {
  const _Compare();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('All server locations', false, true),
      ('Unlimited daily data', false, true),
      ('Full speed & priority servers', false, true),
      ('Stealth mode for restricted networks', true, true),
      ('No ads', false, true),
      ('Up to 5 devices', false, true),
    ];
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: [
          Row(children: [
            const Expanded(child: SizedBox()),
            SizedBox(width: 52, child: Text('Free', textAlign: TextAlign.center, style: t.bodySmall)),
            SizedBox(
              width: 52,
              child: Text('Pro', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: Palette.violet)),
            ),
          ]),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                Expanded(child: Text(r.$1)),
                SizedBox(width: 52, child: _Mark(on: r.$2)),
                SizedBox(width: 52, child: _Mark(on: r.$3, pro: true)),
              ]),
            ),
        ]),
      ),
    );
  }
}

class _Mark extends StatelessWidget {
  const _Mark({required this.on, this.pro = false});
  final bool on;
  final bool pro;
  @override
  Widget build(BuildContext context) => Icon(
        on ? Icons.check_circle_rounded : Icons.remove_rounded,
        size: 20,
        color: on ? (pro ? Palette.violet : Palette.mint) : Palette.line,
      );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.highlight, required this.busy, required this.onBuy});
  final ProductDetails product;
  final bool highlight;
  final bool busy;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight ? Palette.violet.withValues(alpha: 0.12) : Palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: highlight ? Palette.violet : Palette.line, width: highlight ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_cleanTitle(product.title), style: t.titleMedium)),
          if (highlight)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Palette.violet, borderRadius: BorderRadius.circular(8)),
              child: const Text('BEST VALUE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
            ),
        ]),
        const SizedBox(height: 4),
        Text(product.description, style: t.bodySmall),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: highlight ? Palette.violet : Palette.mint,
            foregroundColor: highlight ? Colors.white : Palette.ink,
          ),
          onPressed: busy ? null : onBuy,
          child: busy
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('Subscribe • ${product.price}'),
        ),
      ]),
    );
  }

  // Play appends " (App Name)" to titles.
  String _cleanTitle(String s) => s.replaceAll(RegExp(r'\s*\(.*\)\s*$'), '');
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      );
}
