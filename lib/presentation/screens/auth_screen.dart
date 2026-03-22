import 'package:flutter/material.dart';
import 'package:issueinator/application/controllers/auth_controller.dart';
import 'package:get_it/get_it.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'IssueInator',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 4),
            const Divider(indent: 80, endIndent: 80),
            const SizedBox(height: 4),
            Text(
              'TinkerPlex Issue Triage',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 48),
            ListenableBuilder(
              listenable: GetIt.instance<AuthController>(),
              builder: (context, _) {
                final controller = GetIt.instance<AuthController>();
                return FilledButton.icon(
                  onPressed: controller.isLoading ? null : () => controller.signInWithGoogle(),
                  icon: const Icon(Icons.login),
                  label: controller.isLoading
                      ? const Text('Signing in...')
                      : const Text('Sign in with Google'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
