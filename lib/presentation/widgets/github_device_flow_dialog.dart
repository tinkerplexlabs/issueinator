import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:issueinator/application/controllers/auth_controller.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:get_it/get_it.dart';
import 'package:url_launcher/url_launcher.dart';

/// GitHub device flow authorization using Custom Tabs.
///
/// Shows a bottom sheet with the user code and an "Open GitHub" button.
/// User taps the button, authorizes in the Custom Tab, presses back
/// to return. Sheet detects success and auto-dismisses.
class GitHubDeviceFlowSheet extends StatefulWidget {
  const GitHubDeviceFlowSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const GitHubDeviceFlowSheet(),
    );
  }

  @override
  State<GitHubDeviceFlowSheet> createState() => _GitHubDeviceFlowSheetState();
}

class _GitHubDeviceFlowSheetState extends State<GitHubDeviceFlowSheet> {
  String? _error;
  bool _popScheduled = false;

  @override
  void initState() {
    super.initState();
    final auth = GetIt.instance<AuthController>();
    final githubService = GetIt.instance<GitHubAuthService>();
    auth.addListener(_onAuthChanged);
    auth.startGitHubDeviceFlow(githubService);
  }

  void _onAuthChanged() {
    final auth = GetIt.instance<AuthController>();

    // Auto-dismiss on success with brief delay so user sees the checkmark
    if (auth.isGitHubAuthenticated && mounted && !_popScheduled) {
      _popScheduled = true;
      setState(() {});
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }

    // Check for terminal errors
    if (auth.currentChallenge == null && !auth.isLoading) {
      _error = 'Authorization failed or expired.';
    }

    if (mounted) setState(() {});
  }

  void _openGitHub() {
    final auth = GetIt.instance<AuthController>();
    final challenge = auth.currentChallenge;
    if (challenge == null) return;

    Clipboard.setData(ClipboardData(text: challenge.userCode));
    launchUrl(
      Uri.parse(challenge.verificationUriComplete),
      mode: LaunchMode.inAppBrowserView,
    );
  }

  @override
  void dispose() {
    GetIt.instance<AuthController>().removeListener(_onAuthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = GetIt.instance<AuthController>();
    final challenge = auth.currentChallenge;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Success state
          if (auth.isGitHubAuthenticated) ...[
            const Icon(Icons.check_circle, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            const Text(
              'GitHub connected!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ]

          // Error state
          else if (_error != null) ...[
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                _error = null;
                final githubService = GetIt.instance<GitHubAuthService>();
                auth.startGitHubDeviceFlow(githubService);
                setState(() {});
              },
              child: const Text('Try Again'),
            ),
          ]

          // Loading state (requesting device code)
          else if (challenge == null) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('Connecting to GitHub...'),
          ]

          // Ready state — show code and button
          else ...[
            // Code display
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: challenge.userCode));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Code copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  challenge.userCode,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        letterSpacing: 6,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your code (tap to copy)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 20),

            // Primary action — open GitHub
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openGitHub,
                icon: const Icon(Icons.open_in_browser),
                label: const Text('Open GitHub to Authorize'),
              ),
            ),
            const SizedBox(height: 12),

            // Status indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.grey[400],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Authorize, then press back to return here',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),
          if (!auth.isGitHubAuthenticated)
            TextButton(
              onPressed: () {
                auth.cancelGitHubDeviceFlow();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
