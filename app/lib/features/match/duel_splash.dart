import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../game/game_state.dart';

/// "Face to face": both commanders slide in from the sides with crossed swords between them,
/// hold for a moment, then fade away so the duel question is free. Plays once per duel
/// (keyed by phase id) and never blocks taps.
class DuelSplash extends StatefulWidget {
  const DuelSplash({super.key, required this.attacker, required this.defender, this.delay = Duration.zero});
  final PlayerView attacker;
  final PlayerView defender;
  final Duration delay; // lets the troops' march play first

  @override
  State<DuelSplash> createState() => _DuelSplashState();
}

class _DuelSplashState extends State<DuelSplash> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

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
          if (t >= 1 || !_c.isAnimating && t == 0) return const SizedBox.shrink();
          final inT = Curves.easeOutBack.transform((t / 0.3).clamp(0.0, 1.0));
          final out = t < 0.75 ? 1.0 : 1 - (t - 0.75) / 0.25;
          final swords = Curves.elasticOut.transform(((t - 0.2) / 0.4).clamp(0.0, 1.0));
          return Opacity(
            opacity: out,
            child: Container(
              color: const Color(0xFF02040C).withValues(alpha: 0.82),
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
                            gradient: RadialGradient(colors: [Color(0xFF2A1F6E), Color(0xFF060E22)]),
                            border: Border.fromBorderSide(BorderSide(color: Color(0xFF3FD0FF), width: 2)),
                            boxShadow: [BoxShadow(color: Color(0xCC3FD0FF), blurRadius: 22)],
                          ),
                          child: CustomPaint(painter: _SwordsPainter()),
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
            color: c,
            boxShadow: [BoxShadow(color: c, blurRadius: 16, spreadRadius: 2)],
          ),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.panelDeep),
            child: ClipOval(child: Image.asset(armyOf(player.army).commander, fit: BoxFit.cover)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          player.name,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 22,
            color: AppColors.textPrimary,
            height: 1.2,
            shadows: [Shadow(color: AppColors.neon, blurRadius: 10)],
          ),
        ),
        Text(
          role,
          style: TextStyle(
            color: c,
            fontWeight: FontWeight.w900,
            shadows: [Shadow(color: c, blurRadius: 8)],
          ),
        ),
      ],
    );
  }
}

/// Two crossed swords (drawn, so no emoji font is needed).
class _SwordsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width * 0.3;
    final blade = Paint()
      ..strokeWidth = r * 0.2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE6F7FF);
    final hilt = Paint()
      ..strokeWidth = r * 0.24
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF3FD0FF);
    for (final s in [1.0, -1.0]) {
      canvas.drawLine(c + Offset(-r * s, r), c + Offset(r * s, -r), blade);
      final g = c + Offset(-r * s * 0.55, r * 0.55);
      canvas.drawLine(g + Offset(-r * 0.32, -r * 0.32 * s), g + Offset(r * 0.32, r * 0.32 * s), hilt);
      canvas.drawLine(g, c + Offset(-r * s * 1.05, r * 1.05), hilt);
    }
  }

  @override
  bool shouldRepaint(_SwordsPainter old) => false;
}
