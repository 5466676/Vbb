import 'package:go_router/go_router.dart';

import '../features/game/play_screen.dart';
import '../features/home/home_screen.dart';
import '../features/leaderboard/leaderboard_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/solo/solo_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(path: '/play', builder: (context, state) => const PlayScreen()),
    GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
    GoRoute(path: '/solo', builder: (context, state) => const SoloScreen()),
    GoRoute(path: '/leaderboard', builder: (context, state) => const LeaderboardScreen()),
  ],
);
