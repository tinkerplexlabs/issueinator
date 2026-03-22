import 'package:flutter/material.dart';
import 'package:issueinator/config/dependencies.dart';
import 'package:issueinator/infrastructure/services/supabase_config.dart';
import 'package:issueinator/presentation/widgets/auth_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize(); // MUST be before configureDependencies
  await configureDependencies();
  runApp(const IssueInatorApp());
}

class IssueInatorApp extends StatelessWidget {
  const IssueInatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IssueInator',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0A0A),
          foregroundColor: Color(0xFF00E5FF),
          titleTextStyle: TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFF00E5FF),
          thickness: 2,
        ),
        textTheme: const TextTheme(
          headlineLarge: TextStyle(color: Color(0xFFFF00FF), fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(color: Color(0xFF00FF41), fontWeight: FontWeight.bold),
          headlineSmall: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
          titleLarge: TextStyle(color: Color(0xFFFF00FF)),
          titleMedium: TextStyle(color: Color(0xFF00FF41)),
        ),
        useMaterial3: true,
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00E5FF),
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}
