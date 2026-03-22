import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:issueinator/core/dev_log.dart';

class SupabaseConfig {
  static const String url = 'https://vgvgcfgayqbifsqixerh.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZndmdjZmdheXFiaWZzcWl4ZXJoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI1NDgwODcsImV4cCI6MjA2ODEyNDA4N30.mebuyX9VjkgeDLdveAJgE49TzLr_jVYVVH6ZKkU2SXU';

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static SupabaseClient get client => Supabase.instance.client;

  /// Attempt to refresh the current session if it's expired.
  /// Returns true if a valid session exists afterward, false otherwise.
  /// Never throws — safe to call at startup and on reconnection.
  static Future<bool> refreshSession() async {
    try {
      final session = client.auth.currentSession;
      if (session == null) {
        devLog('[SupabaseConfig] No session to refresh');
        return false;
      }

      devLog('[SupabaseConfig] Refreshing session...');
      await client.auth.refreshSession();
      devLog('[SupabaseConfig] Session refreshed successfully');

      return client.auth.currentSession != null;
    } catch (e) {
      devLog('[SupabaseConfig] Session refresh failed: $e');
      return false;
    }
  }
}
