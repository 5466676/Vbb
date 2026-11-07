import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../../core/map_template.dart';
import '../game/game_state.dart';

/// The war map: painted background, territory overlays in seat colours, values, bases.
/// Zoom and pan with two fingers; tap a territory to pick or attack it.
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.template,
    required this.match,
    required this.highlight,
    required this.selected,
    required this.onTap,
  });

  final MapTemplate template;
  final MatchView match;
  final Set<int> highlight; // legal picks / targets
  final Set<int> selected; // my picks
  final void Function(int territory) onTap;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return LayoutBuilder(
      builder: (context, box) {
        // fit the map inside the box, keeping its aspect ratio
        var w = box.maxWidth, h = w / t.aspect;
        if (h > box.maxHeight) {
          h = box.maxHeight;
          w = h * t.aspect;
        }
        final size = Size(w, h);
        return Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            boundaryMargin: const EdgeInsets.all(40),
            child: SizedBox(
              width: w,
              height: h,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final n = Offset(d.localPosition.dx / w, d.localPosition.dy / h);
                  for (final s in t.territories) {
                    if (s.contains(n)) {
                      widget.onTap(s.id);
                      return;
                    }
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(t.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => CustomPaint(
                          size: size,
                          painter: _MapPainter(
                            template: t,
                            match: widget.match,
                            highlight: widget.highlight,
                            selected: widget.selected,
                            pulse: widget.highlight.isEmpty && widget.match.flash == null ? 0 : _pulse.value,
                          ),
                        ),
                      ),
                    ),
                    ..._bases(size),
                    ..._labels(size),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Iterable<Widget> _bases(Size size) sync* {
    final m = widget.match;
    for (final terr in m.territories.values.where((x) => x.isBase && x.owner != null)) {
      final shape = widget.template.byId(terr.id);
      final d = size.height * 0.13;
      yield Positioned(
        left: shape.label.dx * size.width - d / 2,
        top: shape.label.dy * size.height - d * 0.95,
        width: d,
        height: d,
        child: IgnorePointer(child: Image.asset(armyOf(m.players[terr.owner!].army).fort, fit: BoxFit.contain)),
      );
    }
  }

  Iterable<Widget> _labels(Size size) sync* {
    final m = widget.match;
    final fs = max(9.0, size.height * 0.028);
    for (final shape in widget.template.territories) {
      final terr = m.territories[shape.id];
      if (terr == null || terr.owner == null) continue;
      final color = AppColors.seat(terr.owner);
      yield Positioned(
        left: shape.label.dx * size.width - 40,
        top: shape.label.dy * size.height + (terr.isBase ? fs * 0.3 : -fs * 0.8),
        width: 80,
        child: IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: fs * 0.4),
                decoration: BoxDecoration(
                  color: AppColors.parchment.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(fs),
                  border: Border.all(color: color, width: 1.6),
                ),
                child: Text(
                  '${terr.value}',
                  style: TextStyle(fontSize: fs, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.3),
                ),
              ),
              if (terr.isBase) Text('🏰' * terr.towers, style: TextStyle(fontSize: fs * 0.75, height: 1.2)),
              if (terr.shielded) Text('🛡', style: TextStyle(fontSize: fs * 0.9)),
            ],
          ),
        ),
      );
    }
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({
    required this.template,
    required this.match,
    required this.highlight,
    required this.selected,
    required this.pulse,
  });

  final MapTemplate template;
  final MatchView match;
  final Set<int> highlight;
  final Set<int> selected;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    // sea routes
    final sea = Paint()
      ..color = const Color(0xCC1B3B5A)
      ..strokeWidth = size.height * 0.004
      ..style = PaintingStyle.stroke;
    for (final s in template.seaLinks) {
      _dashed(
        canvas,
        Offset(s.from.dx * size.width, s.from.dy * size.height),
        Offset(s.to.dx * size.width, s.to.dy * size.height),
        sea,
      );
    }

    for (final shape in template.territories) {
      final path = shape.path(size);
      final terr = match.territories[shape.id];
      final owner = terr?.owner;
      if (owner != null) {
        fill.color = AppColors.seat(owner).withValues(alpha: 0.42);
        canvas.drawPath(path, fill);
      }
      if (highlight.contains(shape.id)) {
        fill.color = AppColors.gold.withValues(alpha: 0.18 + 0.22 * pulse);
        canvas.drawPath(path, fill);
      }
      if (selected.contains(shape.id)) {
        fill.color = AppColors.gold.withValues(alpha: 0.55);
        canvas.drawPath(path, fill);
      }
      if (match.flash == shape.id || match.duelTerritory == shape.id) {
        fill.color = Colors.white.withValues(alpha: 0.15 + 0.25 * pulse);
        canvas.drawPath(path, fill);
      }
      stroke
        ..color = owner != null ? AppColors.seat(owner) : const Color(0x66392A18)
        ..strokeWidth = owner != null ? size.height * 0.004 : size.height * 0.0022;
      canvas.drawPath(path, stroke);
      if (highlight.contains(shape.id)) {
        stroke
          ..color = AppColors.gold
          ..strokeWidth = size.height * (0.004 + 0.003 * pulse);
        canvas.drawPath(path, stroke);
      }
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint p) {
    final d = (b - a).distance;
    final dir = (b - a) / d;
    const dash = 6.0, gap = 5.0;
    for (var t = 0.0; t < d; t += dash + gap) {
      c.drawLine(a + dir * t, a + dir * min(t + dash, d), p);
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => true;
}
