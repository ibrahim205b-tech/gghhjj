/// Build-time configuration (passed with --dart-define). These are PUBLIC
/// client values: the Supabase publishable/anon key and Firebase client
/// options are meant to ship inside apps; data is protected by RLS.
/// Server secrets (service role, FCM credentials) never appear here.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const firebaseSenderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');

  static const oauthRedirect = 'com.enjaz.student://login-callback';

  static bool get backendConfigured => supabaseUrl.startsWith('https://') && supabaseAnonKey.isNotEmpty;
  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;
}
