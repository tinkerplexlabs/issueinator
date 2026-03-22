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
            FilledButton(
              onPressed: () => GetIt.instance<AuthController>().signInAnonymously(),
              child: const Text('Sign In (Dev Mode)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: Full Google SSO in Phase 1-02 checkpoint',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
