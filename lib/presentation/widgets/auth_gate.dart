import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:issueinator/application/controllers/auth_controller.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';
import 'package:issueinator/presentation/screens/home_screen.dart';
import 'package:issueinator/presentation/screens/auth_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<sb.AuthState>(
      stream: SupabaseConfig.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session;
        // Keep AuthController in sync with auth state changes
        GetIt.instance<AuthController>().updateFromAuthState(session);
        if (session != null) {
          return const HomeScreen();
        }
        return const AuthScreen();
      },
    );
  }
}
