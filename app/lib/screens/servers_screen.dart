import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'plans_screen.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final regions = app.boot?.regions ?? const <Region>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Choose location')),
      body: RefreshIndicator(
        onRefresh: () => app.refresh(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Tile(
              leading: const Icon(Icons.bolt_rounded, color: Palette.mint),
              title: 'Fastest server',
              subtitle: 'Automatically picks the least loaded server',
              selected: app.region == 'auto',
              onTap: () {
                app.setRegion('auto');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text('All locations', style: Theme.of(context).textTheme.bodySmall),
            ),
            for (final r in regions) ...[
              _Tile(
                leading: Text(r.flag, style: const TextStyle(fontSize: 26)),
                title: r.name,
                subtitle: !r.available
                    ? 'Temporarily unavailable'
                    : '${r.stealth ? 'Stealth ready • ' : ''}Load ${r.load}%',
                trailing: r.locked
                    ? const Icon(Icons.lock_rounded, color: Palette.violet, size: 20)
                    : _LoadDot(load: r.load, available: r.available),
                selected: app.region == r.code,
                onTap: () {
                  if (r.locked) {
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlansScreen()));
                    return;
                  }
                  if (!r.available) return;
                  app.setRegion(r.code);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 10),
            ],
            if (regions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('No locations available right now.')),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.trailing,
  });
  final Widget leading;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Material(
      color: selected ? Palette.mint.withValues(alpha: 0.10) : Palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? Palette.mint : Palette.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            SizedBox(width: 40, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: t.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: t.bodySmall),
              ]),
            ),
            if (trailing != null) trailing!,
            if (selected) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle_rounded, color: Palette.mint),
            ],
          ]),
        ),
      ),
    );
  }
}

class _LoadDot extends StatelessWidget {
  const _LoadDot({required this.load, required this.available});
  final int load;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final c = !available
        ? Palette.line
        : load < 60
            ? Palette.mint
            : load < 85
                ? Palette.amber
                : Palette.coral;
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }
}
