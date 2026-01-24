import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'theme/slate_theme.dart';
import 'screens/home.dart';
import 'store.dart'; // Ensure you created this file from the previous step

Future<void> main() async {
  // 1. Ensure bindings are initialized first
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Load the .env file
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Warning: Failed to load .env file: $e");
  }

  // 3. Initialize the UserStore (Loads Session ID from Secure Storage)
  // We await this so the app knows the login state before the first frame.
  await UserStore().init();

  runApp(const ProjectDupesApp());
}

class ProjectDupesApp extends StatelessWidget {
  const ProjectDupesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Project Dupes',
      debugShowCheckedModeBanner: false,
      theme: SlateTheme.lightTheme,
      darkTheme: SlateTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

// ROUTING CONFIGURATION
final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => HomeScreen(
        // We still pass query params to handle deep links from external sources (e.g., email magic links)
        code: state.uri.queryParameters['code'],
        email: state.uri.queryParameters['email'],
        error: state.uri.queryParameters['error'],
      ),
    ),
    GoRoute(
      path: '/login-callback',
      builder: (context, state) {
        return HomeScreen(
          code: state.uri.queryParameters['code'],
          email: state.uri.queryParameters['email'],
          error: state.uri.queryParameters['error'],
        );
      },
    ),
  ],
);
