import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../game/game_state.dart';

/// "Face to face": both commanders slide in from the sides with crossed swords between them,
/// hold for a moment, then fade away so the duel question is free. Plays once per duel
/// (keyed by phase id) and never blocks taps.
class DuelSplash extends StatefulWidget {
  const DuelSplash({super.key, required this.attacker, required this.defender});
  final PlayerView attacker;
  final PlayerView defender;

  @override
  State<DuelSplash> createState() => _DuelSplashState();
}

class _DuelSplashState extends State<DuelSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          if (t >= 1) return const SizedBox.shrink();
          final inT = Curves.easeOutBack.transform((t / 0.3).clamp(0.0, 1.0));
          final out = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
          final swords = Curves.elasticOut.transform(((t - 0.2) / 0.4).clamp(0.0, 1.0));
          return Opacity(
            opacity: out,
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  final portrait = (box.maxHeight * 0.42).clamp(90.0, 190.0);
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // attacker on the right (RTL reading starts there), defender on the left
                      Positioned(
                        left: w * 0.5 + 40 - (1 - inT) * w * 0.5,
                        child: _Side(player: widget.attacker, role: 'المهاجم', size: portrait),
                      ),
                      Positioned(
                        right: w * 0.5 + 40 - (1 - inT) * w * 0.5,
                        child: _Side(player: widget.defender, role: 'المدافع', size: portrait),
                      ),
                      Transform.scale(
                        scale: swords,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [Color(0xFFC0392B), Color(0xFF5E140D)]),
                            boxShadow: [BoxShadow(color: Color(0xAAFFC864), blurRadius: 18)],
                          ),
                          child: const Center(
                            child: Text('⚔', style: TextStyle(fontSize: 38, color: Colors.white, height: 1.1)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({required this.player, required this.role, required this.size});
  final PlayerView player;
  final String role;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.seat(player.seat);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFFF0CF7A), Color(0xFF8A5A17)]),
            boxShadow: [BoxShadow(color: c, blurRadius: 16, spreadRadius: 2)],
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            child: ClipOval(child: Image.asset(armyOf(player.army).commander, fit: BoxFit.cover)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          player.name,
          style: const TextStyle(
            fontFamily: AppTheme.headingFont,
            fontSize: 26,
            color: AppColors.textPrimary,
            height: 1.2,
            shadows: [Shadow(color: Colors.black, blurRadius: 4)],
          ),
        ),
        Text(
          role,
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w900,
            shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
          ),
        ),
      ],
    );
  }
}
