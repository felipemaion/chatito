import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import 'screens/contact_detail_screen.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';

/// Notifica o GoRouter quando a sessão muda (registro → redireciona).
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider.family<GoRouter, String?>((
  ref,
  initialLocation,
) {
  final listenable = _SessionListenable(ref);
  ref.onDispose(listenable.dispose);
  return GoRouter(
    initialLocation: initialLocation ?? '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final registered = ref.read(sessionProvider).isRegistered;
      final onboarding = state.matchedLocation == '/onboarding';
      if (!registered && !onboarding) return '/onboarding';
      if (registered && onboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeShell()),
      GoRoute(
        path: '/c/:id',
        builder: (_, s) => HomeShell(selectedConvId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/contact/:userId',
        builder: (_, s) =>
            ContactDetailScreen(userId: s.pathParameters['userId']!),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    ],
  );
});
