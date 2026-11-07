import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';

/// App routes. Splash, lobby, match and results screens arrive in phase 6.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
  ],
);
