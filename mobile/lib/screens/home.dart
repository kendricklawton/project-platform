import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:project_dupes/services.dart';
import 'package:project_dupes/store.dart';

class HomeScreen extends StatefulWidget {
  final String? code;
  final String? email;
  final String? error;

  const HomeScreen({super.key, this.code, this.email, this.error});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();

    // SYNC: If the app was opened via a deep link (URL params),
    // we sync that data to the Store.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = UserStore();

      // If the URL contains an error (e.g. from the backend redirect)
      if (widget.error != null) {
        store.setLoginFailure(widget.error!);
        // Clear the URL so a refresh doesn't trigger the error again
        context.go('/');
      }
      // If the URL contains success data (rare in manual flow, but good for deep links)
      else if (widget.code != null && widget.email != null) {
        // Note: In a real app, 'code' might need to be exchanged for a session here
        // if it wasn't done by the service layer.
        // For now, we treat the incoming params as valid session data.
        store.setLoginSuccess(widget.code!, widget.email!);
        context.go('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // LISTEN: This builder rebuilds the Scaffold whenever UserStore changes
    return ListenableBuilder(
      listenable: UserStore(),
      builder: (context, child) {
        final store = UserStore();

        // 1. Loading State (optional, if main.dart didn't await init)
        if (store.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Project Dupes',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: _buildView(context, store),
            ),
          ),
        );
      },
    );
  }

  Widget _buildView(BuildContext context, UserStore store) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Error Display from Store
        if (store.error != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  LucideIcons.circleAlert,
                  size: 20,
                  color: Colors.red,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    "Login Failed: ${store.error}",
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],

        // Main Icon
        GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                behavior: SnackBarBehavior.floating,
                content: Text(
                  store.isLoggedIn
                      ? "Scanner Active (Mock)"
                      : "Please Sign In first",
                ),
              ),
            );
          },
          child: Icon(
            LucideIcons.qrCode,
            size: 140,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),

        const SizedBox(height: 16),

        Text(
          "Tap icon to scan",
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 48),

        // Auth Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              elevation: store.isLoggedIn ? 0 : 4,
              shape: const StadiumBorder(),
              backgroundColor: store.isLoggedIn
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.primary,
              foregroundColor: store.isLoggedIn
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onPrimary,
            ),
            icon: Icon(
              store.isLoggedIn ? LucideIcons.logOut : LucideIcons.logIn,
              size: 24,
            ),
            label: Text(store.isLoggedIn ? "Sign Out" : "Sign In"),
            onPressed: () => _handleAuthAction(context, store),
          ),
        ),
      ],
    );
  }

  Future<void> _handleAuthAction(BuildContext context, UserStore store) async {
    if (store.isLoggedIn) {
      // 1. Logout Action
      await AuthService().logout();
      await store.logout(); // Updates UI and SecureStorage
    } else {
      // 2. Login Action
      try {
        final result = await AuthService().beginLoginFlow();

        // Note: You should update your AuthService to return the session_id
        // if you want true persistence. For now, we use what 'result' has.
        // If AuthService stored session internally, we assume we are good.

        final sessionCode = result['code'] ?? "";
        final email = result['email'] ?? "Unknown";

        // Update Store -> Triggers UI rebuild
        // Ideally, pass the real session ID here, not the handoff code.
        await store.setLoginSuccess(sessionCode, email);
      } catch (e) {
        store.setLoginFailure(e.toString());
      }
    }
  }
}
