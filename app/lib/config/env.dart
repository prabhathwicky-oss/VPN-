/// Build-time configuration, injected with --dart-define (see .github/workflows/android.yml).
/// AdMob values default to Google's official TEST ids so debug builds never
/// serve real ads.
class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const admobBannerId = String.fromEnvironment(
    'ADMOB_BANNER_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );
  static const admobInterstitialId = String.fromEnvironment(
    'ADMOB_INTERSTITIAL_ID',
    defaultValue: 'ca-app-pub-3940256099942544/1033173712',
  );

  static const privacyUrl = String.fromEnvironment(
    'PRIVACY_URL',
    defaultValue: 'https://example.com/privacy',
  );
  static const termsUrl = String.fromEnvironment(
    'TERMS_URL',
    defaultValue: 'https://example.com/terms',
  );
  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@example.com',
  );

  static const appName = String.fromEnvironment('APP_NAME', defaultValue: 'YPN VPN');
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0');
  static const androidPackage = String.fromEnvironment('ANDROID_PACKAGE', defaultValue: 'com.ypnvpn.app');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
