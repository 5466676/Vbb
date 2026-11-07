import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../lobby/lobby_screen.dart';
import '../match/match_screen.dart';
import 'game_controller.dart';

/// Shows the lobby or the match, whichever the server says we are in.
/// Goes back to the menu when we leave the room.
class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key});

  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  bool _sawRoom = false;

  @override
  Widget build(BuildContext context) {
    final gs = ref.watch(gameProvider);
    ref.listen(gameProvider.select((s) => s.error), (_, err) {
      if (err == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      ref.read(gameProvider.notifier).clearError();
      if (!_sawRoom && gs.room == null) context.pop(); // join failed
    });
    if (gs.room != null) _sawRoom = true;
    if (_sawRoom && gs.room == null && gs.match == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.canPop()) context.pop();
      });
    }
    if (gs.match != null) return const MatchScreen();
    if (gs.room != null) return const LobbyScreen();
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.gold),
            const SizedBox(height: 16),
            Text(gs.queued != null ? 'عم ندوّر على لاعبين… (${gs.queued!['size']})' : 'عم نتصل…'),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                if (gs.queued != null) ref.read(gameProvider.notifier).cancelQuickMatch();
                context.pop();
              },
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );
  }
}
