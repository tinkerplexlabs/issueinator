import 'package:get_it/get_it.dart';
import 'package:issueinator/application/controllers/auth_controller.dart';
import 'package:issueinator/domain/services/github_auth_service.dart';
import 'package:issueinator/infrastructure/persistence/local_storage.dart';
import 'package:issueinator/infrastructure/services/github_auth_service_impl.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  // Infrastructure — persistence
  getIt.registerSingleton<LocalStorage>(SharedPreferencesLocalStorage());

  // GitHub auth service (device flow + secure storage)
  getIt.registerSingleton<GitHubAuthService>(GitHubAuthServiceImpl());

  // Auth controller (Supabase + GitHub)
  getIt.registerSingleton<AuthController>(AuthController());
}
