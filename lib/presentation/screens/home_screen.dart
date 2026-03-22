import 'package:flutter/material.dart';
import 'package:issueinator/application/controllers/auth_controller.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';
import 'package:issueinator/presentation/widgets/github_device_flow_dialog.dart'
    show GitHubDeviceFlowSheet;
import 'package:issueinator/core/dev_log.dart';
import 'package:get_it/get_it.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _products = [];
  List<String> _productColumns = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    // Validate GitHub token on every HomeScreen load (not just first launch)
    GetIt.instance<AuthController>().validateGitHubToken(
      GetIt.instance<GitHubAuthService>(),
    );
  }

  Future<void> _loadProducts() async {
    try {
      // Load products — column discovery via information_schema is not
      // available through PostgREST. Use select('*') and log the keys
      // from the first row to discover the schema at runtime.
      final products = await SupabaseConfig.client
          .from('products')
          .select('*')
          .order('name');
      devLog('[HomeScreen] Loaded ${(products as List).length} products');
      if ((products as List).isNotEmpty) {
        _productColumns = products.first.keys.toList();
        devLog('[HomeScreen] products columns: $_productColumns');
      }

      setState(() {
        _products = (products).cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      devLog('[HomeScreen] Error loading products: $e');
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = GetIt.instance<AuthController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('IssueInator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Developer UID: ${auth.currentUser?.id ?? "unknown"}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Products table columns: ${_productColumns.join(", ")}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text('GitHub Integration', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    // GitHub auth status row (Plan 01-03)
                    ListenableBuilder(
                      listenable: GetIt.instance<AuthController>(),
                      builder: (context, _) {
                        final authCtrl = GetIt.instance<AuthController>();
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                authCtrl.isGitHubAuthenticated
                                    ? Icons.check_circle
                                    : Icons.warning,
                                color: authCtrl.isGitHubAuthenticated
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                authCtrl.isGitHubAuthenticated
                                    ? 'GitHub: Connected'
                                    : 'GitHub: Not connected',
                              ),
                              const Spacer(),
                              if (!authCtrl.isGitHubAuthenticated)
                                FilledButton.tonal(
                                  onPressed: () =>
                                      GitHubDeviceFlowSheet.show(context),
                                  child: const Text('Connect GitHub'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text('Products', style: Theme.of(context).textTheme.titleMedium),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _products.length,
                        itemBuilder: (context, index) {
                          final p = _products[index];
                          return ListTile(
                            title: Text(p['name']?.toString() ?? 'Unknown'),
                            subtitle: Text(
                              p.keys.where((k) => k != 'name').join(', '),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
