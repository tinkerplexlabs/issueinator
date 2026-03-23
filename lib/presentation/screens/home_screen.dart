import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get_it/get_it.dart';
import 'package:issueinator/application/controllers/auth_controller.dart';
import 'package:issueinator/application/controllers/dashboard_controller.dart';
import 'package:issueinator/core/dev_log.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';
import 'package:issueinator/presentation/screens/report_list_screen.dart';
import 'package:issueinator/presentation/widgets/github_device_flow_dialog.dart'
    show GitHubDeviceFlowSheet;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
      final products = await SupabaseConfig.client
          .from('products')
          .select('name')
          .order('name');
      devLog('[HomeScreen] Loaded ${(products as List).length} products');

      final productNames = (products as List)
          .map((p) => (p as Map<String, dynamic>)['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();

      await GetIt.instance<DashboardController>().loadCounts(productNames);

      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    } catch (e) {
      devLog('[HomeScreen] Error loading products: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
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
            icon: SvgPicture.asset(
              'assets/images/logout-icon.svg',
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(
                Theme.of(context).appBarTheme.foregroundColor ?? Colors.white,
                BlendMode.srcIn,
              ),
            ),
            onPressed: () => auth.signOut(),
          ),
          const SizedBox(width: 56),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _loadProducts();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Admin account indicator
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: auth.isAdmin
                          ? Colors.green.withAlpha(30)
                          : Colors.red.withAlpha(30),
                      child: Row(
                        children: [
                          Icon(
                            auth.isAdmin
                                ? Icons.admin_panel_settings
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color:
                                auth.isAdmin ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              auth.isAdmin
                                  ? 'Signed in as admin (${auth.currentUser?.email ?? auth.currentUser?.id})'
                                  : 'Not signed in as admin — bug reports will not load. Sign out and use the admin account.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: auth.isAdmin
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // GitHub Integration section (preserved from original)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        'GitHub Integration',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    ListenableBuilder(
                      listenable: GetIt.instance<AuthController>(),
                      builder: (context, _) {
                        final authCtrl = GetIt.instance<AuthController>();
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Text(
                        'Products',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    // Dashboard product count cards
                    Expanded(
                      child: ListenableBuilder(
                        listenable: GetIt.instance<DashboardController>(),
                        builder: (context, _) {
                          final controller =
                              GetIt.instance<DashboardController>();

                          if (controller.isLoading) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          if (controller.error != null) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Error: ${controller.error}'),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: () => _loadProducts(),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (controller.counts.isEmpty) {
                            return const Center(
                                child: Text('No products found'));
                          }

                          final isAdmin =
                              GetIt.instance<AuthController>().isAdmin;

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: controller.counts.length,
                            itemBuilder: (context, index) {
                              final count = controller.counts[index];
                              final name = count.productName;
                              final displayName = name.isNotEmpty
                                  ? '${name[0].toUpperCase()}${name.substring(1)}'
                                  : name;
                              final hasUnprocessed =
                                  isAdmin && count.unprocessedCount > 0;

                              return Card(
                                margin:
                                    const EdgeInsets.symmetric(vertical: 6),
                                color: hasUnprocessed
                                    ? const Color(0xFF3D2E1E)
                                    : null,
                                elevation: hasUnprocessed ? 3 : 1,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: isAdmin
                                      ? () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  ReportListScreen(
                                                productName:
                                                    count.productName,
                                              ),
                                            ),
                                          );
                                        }
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                displayName,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          hasUnprocessed
                                                              ? FontWeight
                                                                  .bold
                                                              : null,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                isAdmin
                                                    ? '${count.totalCount} report${count.totalCount == 1 ? '' : 's'}'
                                                    : '— reports',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isAdmin
                                                ? (hasUnprocessed
                                                    ? Colors.orange
                                                        .withAlpha(30)
                                                    : Colors.green
                                                        .withAlpha(30))
                                                : Colors.grey.withAlpha(30),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isAdmin
                                                    ? (hasUnprocessed
                                                        ? Icons
                                                            .pending_outlined
                                                        : Icons
                                                            .check_circle_outline)
                                                    : Icons.lock_outline,
                                                size: 16,
                                                color: isAdmin
                                                    ? (hasUnprocessed
                                                        ? Colors.orange
                                                        : Colors.green)
                                                    : Colors.grey,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                isAdmin
                                                    ? '${count.unprocessedCount} unprocessed'
                                                    : '—',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: isAdmin
                                                          ? (hasUnprocessed
                                                              ? Colors
                                                                  .deepOrange
                                                              : Colors.green)
                                                          : Colors.grey,
                                                      fontWeight:
                                                          hasUnprocessed
                                                              ? FontWeight
                                                                  .bold
                                                              : null,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
