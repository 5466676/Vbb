import 'dart:math';

import 'package:flutter/material.dart';

import 'question_arena.dart' show Toon;

/// A big glowing notice window that drops on two light chains to announce a stage ("تقاسم الأرض", "الحرب!",
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
          // sized from the screen: chains reach down a fifth of the height, the plank sits below
          // them (scaled down if needed), so the sign is whole even on a phone in landscape
          return LayoutBuilder(
            builder: (context, box) {
              final chainH = box.maxHeight * 0.2;
              final travel = chainH + box.maxHeight * 0.45;
              final dy = -travel * (1 - drop) - travel * 1.2 * lift;
              return Align(
                alignment: Alignment.topCenter,
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform.rotate(
                    angle: 0.04 * (1 - drop) - 0.02 * lift,
                    child: _Sign(
                      text: widget.text,
                      sub: widget.sub,
                      chainH: chainH,
                      maxPlank: Size(box.maxWidth * 0.9, box.maxHeight * 0.42),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Sign extends StatelessWidget {
  const _Sign({required this.text, this.sub, required this.chainH, required this.maxPlank});
  final String text;
  final String? sub;
  final double chainH;
  final Size maxPlank;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // chains
        SizedBox(
          width: min(300, maxPlank.width * 0.8),
          height: chainH,
          child: CustomPaint(painter: _ChainsPainter()),
        ),
        ConstrainedBox(
          constraints: BoxConstraints.loose(maxPlank),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Container(
              constraints: const BoxConstraints(minWidth: 320),
              padding: const EdgeInsets.fromLTRB(36, 12, 36, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Toon.outline, width: 2),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xF2102A57), Color(0xF5060E22)],
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0xCC3FD0FF), blurRadius: 18),
                  BoxShadow(color: Color(0x99000000), blurRadius: 16, offset: Offset(0, 10)),
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
                        fontWeight: FontWeight.w900,
                        fontSize: 38,
                        height: 1.3,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Toon.outline, blurRadius: 14),
                          Shadow(color: Toon.outline, blurRadius: 4),
                        ],
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF9FE6FF),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          shadows: [Shadow(color: Toon.outline, blurRadius: 6)],
                        ),
                      ),
                  ],
                ),
              ),
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
      ..strokeWidth = 2
      ..color = const Color(0xFFBFF0FF);
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..color = const Color(0x803FD0FF);
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
      ..color = const Color(0x333FD0FF)
      ..strokeWidth = 2;
    // plank seams and nails
    canvas.drawLine(Offset(-30, size.height / 2), Offset(size.width + 30, size.height / 2), seam);
    final nail = Paint()..color = const Color(0xFF3FD0FF);
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
