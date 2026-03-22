import 'package:get_it/get_it.dart';
import 'package:issueinator/application/controllers/auth_controller.dart';
import 'package:issueinator/application/controllers/dashboard_controller.dart';
import 'package:issueinator/application/controllers/report_list_controller.dart';
import 'package:issueinator/application/controllers/sync_controller.dart';
import 'package:issueinator/application/controllers/triage_controller.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/domain/services/github_sync_service.dart';
import 'package:issueinator/infrastructure/persistence/local_storage.dart';
import 'package:issueinator/infrastructure/repositories/bug_report_repository.dart';
import 'package:issueinator/infrastructure/services/github_auth_service_impl.dart';
import 'package:issueinator/infrastructure/services/github_sync_service_impl.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // Infrastructure — persistence
  getIt.registerSingleton<LocalStorage>(SharedPreferencesLocalStorage());

  // GitHub auth service (device flow + secure storage)
  getIt.registerSingleton<GitHubAuthService>(GitHubAuthServiceImpl());

  // Auth controller (Supabase + GitHub)
  getIt.registerSingleton<AuthController>(AuthController());

  // Bug report data layer
  getIt.registerSingleton<BugReportRepository>(BugReportRepository());

  // Dashboard controller (product counts)
  getIt.registerSingleton<DashboardController>(
    DashboardController(getIt<BugReportRepository>()),
  );

  // Report list controller (per-product report list)
  getIt.registerSingleton<ReportListController>(
    ReportListController(getIt<BugReportRepository>()),
  );

  // Triage controller (write triage tags and comments)
  getIt.registerSingleton<TriageController>(
    TriageController(getIt<BugReportRepository>()),
  );

  // GitHub sync service (issue creation + dedup)
  getIt.registerSingleton<GitHubSyncService>(
    GitHubSyncServiceImpl(
      getIt<GitHubAuthService>(),
      getIt<BugReportRepository>(),
    ),
  );

  // Sync controller (UI state for GitHub sync)
  getIt.registerSingleton<SyncController>(
    SyncController(getIt<GitHubSyncService>()),
  );
}
