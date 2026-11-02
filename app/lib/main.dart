import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/ads_service.dart';
import 'services/api.dart';
import 'services/billing_service.dart';
import 'services/storage.dart';
import 'services/vpn_engine.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Palette.ink,
  ));

  if (!Env.isConfigured) {
    runApp(const _MisconfiguredApp());
    return;
  }

  await Supabase.initialize(url: Env.supabaseUrl, anonKey: Env.supabaseAnonKey);
  final storage = await Storage.open();
  final api = Api();
  final ads = AdsService();
  final state = AppState(api: api, storage: storage, engine: VpnEngine(), ads: ads);
  final billing = BillingService(api)..onEntitlementChanged = () => state.refresh();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider.value(value: billing),
      Provider.value(value: storage),
      Provider.value(value: api),
    ],
    child: YpnApp(storage: storage),
  ));
}

class YpnApp extends StatelessWidget {
  const YpnApp({super.key, required this.storage});
  final Storage storage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Env.appName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: storage.onboarded ? const RootGate() : const OnboardingScreen(),
    );
  }
}

/// Starts the app state once and shows splash / error / home.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      await app.init();
      final products = app.boot?.products.values.toSet() ?? <String>{};
      if (mounted) await context.read<BillingService>().init(products);
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.loading && app.boot == null) return const _Splash();
    if (app.fatalError != null && app.boot == null) {
      return _ErrorScreen(message: app.fatalError!, onRetry: () => app.init());
    }
    return const HomeScreen();
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shield_rounded, size: 72, color: Palette.mint),
          SizedBox(height: 16),
          Text(Env.appName, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Palette.text)),
          SizedBox(height: 28),
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.cloud_off_rounded, size: 64, color: Palette.muted),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ]),
        ),
      ),
    );
  }
}

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: buildTheme(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This build is missing SUPABASE_URL / SUPABASE_ANON_KEY.\n'
              'Add them as GitHub secrets and rebuild.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
