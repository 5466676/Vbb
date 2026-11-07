import 'package:flutter/material.dart';

import 'question_arena.dart' show Toon;

/// A big wooden sign that drops on two chains to announce a stage ("تقاسم الأرض", "الحرب!",
/// "الجولة 3"…), swings, holds, then lifts away. Plays once per announcement (keyed by its id)
/// and never blocks taps.
class StageSign extends StatefulWidget {
  const StageSign({super.key, required this.text, this.sub});
  final String text;
  final String? sub;

  @override
  State<StageSign> createState() => _StageSignState();
}

class _StageSignState extends State<StageSign> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
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
        builder: (context, child) {
          final t = _c.value;
          if (t >= 1) return const SizedBox.shrink();
          final drop = Curves.bounceOut.transform((t / 0.3).clamp(0.0, 1.0));
          final lift = Curves.easeInBack.transform(((t - 0.82) / 0.18).clamp(0.0, 1.0));
          final y = -1.0 + drop - lift * 1.2; // fraction of the sign's travel
          return Align(
            alignment: Alignment(0, -0.35 + y * 1.3),
            child: Transform.rotate(angle: 0.04 * (1 - drop) - 0.02 * lift, child: child),
          );
        },
        child: _Sign(text: widget.text, sub: widget.sub),
      ),
    );
  }
}

class _Sign extends StatelessWidget {
  const _Sign({required this.text, this.sub});
  final String text;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // chains
        SizedBox(width: 300, height: 300, child: CustomPaint(painter: _ChainsPainter())),
        Container(
          constraints: const BoxConstraints(minWidth: 320),
          padding: const EdgeInsets.fromLTRB(36, 12, 36, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Toon.outline, width: 3.5),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFC98A4B), Color(0xFF9A5E2C)],
            ),
            boxShadow: const [
              BoxShadow(color: Toon.outline, offset: Offset(0, 6)),
              BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 10)),
            ],
          ),
          child: CustomPaint(
            painter: _PlanksPainter(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Ruqaa',
                    fontSize: 44,
                    height: 1.25,
                    color: Color(0xFFFFF3D6),
                    shadows: [
                      Shadow(color: Toon.outline, offset: Offset(0, 3)),
                      Shadow(color: Toon.outline, blurRadius: 2),
                    ],
                  ),
                ),
                if (sub != null)
                  Text(
                    sub!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFE8B0),
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      shadows: [Shadow(color: Toon.outline, offset: Offset(0, 1.5))],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChainsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final link = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = const Color(0xFF8C8C8C);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..color = Toon.outline;
    for (final x in [size.width * 0.2, size.width * 0.8]) {
      for (var y = 0.0; y < size.height; y += 16) {
        final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y + 8), width: 10, height: 18),
          const Radius.circular(5),
        );
        canvas.drawRRect(r, edge);
        canvas.drawRRect(r, link);
      }
    }
  }

  @override
  bool shouldRepaint(_ChainsPainter old) => false;
}

class _PlanksPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final seam = Paint()
      ..color = const Color(0x553A2414)
      ..strokeWidth = 2;
    // plank seams and nails
    canvas.drawLine(Offset(-30, size.height / 2), Offset(size.width + 30, size.height / 2), seam);
    final nail = Paint()..color = const Color(0xFF5A3A1E);
    for (final p in [
      const Offset(-22, 6),
      Offset(size.width + 22, 6),
      Offset(-22, size.height - 6),
      Offset(size.width + 22, size.height - 6),
    ]) {
      canvas.drawCircle(p, 4, nail);
    }
  }

  @override
  bool shouldRepaint(_PlanksPainter old) => false;
}
