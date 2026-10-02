/// Compile-time configuration.
///
/// Values come from `--dart-define-from-file=env.json` (see README). The anon
/// key is a public key, but it is still kept out of source control.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
