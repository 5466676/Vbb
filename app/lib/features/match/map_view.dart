import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../../app/theme.dart';
import '../../core/armies.dart';
import '../../core/map_template.dart';
import '../game/game_state.dart' hide Ticker;

/// The war map: painted background, territories washed in seat colours with ink borders,
/// value banners, forts, and a short-lived effects layer (march arrows, flags, falling towers).
/// Three layers repaint independently: ownership (only when it changes), highlight (pulses
/// only while something is selectable) and effects (only while an effect runs).
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.template,
    required this.match,
    required this.highlight,
    required this.selected,
    required this.onTap,
    this.version = 0,
  });

  final MapTemplate template;
  final MatchView match;
  final Set<int> highlight; // legal picks / targets
  final Set<int> selected; // my picks
  final void Function(int territory) onTap;
  final int version; // bumps when the match changes (it is mutated in place)

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didUpdateWidget(MapView old) {
    super.didUpdateWidget(old);
    _syncPulse();
  }

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  void _syncPulse() {
    final active = widget.highlight.isNotEmpty || widget.match.duelTerritory != null;
    if (active && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!active && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

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
        final owners = _ownerKey();
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
                      child: CustomPaint(
                        size: size,
                        painter: _OwnershipPainter(template: t, match: widget.match, key: owners),
                      ),
                    ),
                    RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => CustomPaint(
                          size: size,
                          painter: _HighlightPainter(
                            template: t,
                            highlight: widget.highlight,
                            selected: widget.selected,
                            duel: widget.match.duelTerritory,
                            t: _pulse.value,
                          ),
                        ),
                      ),
                    ),
                    ..._bases(size),
                    ..._labels(size),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _EffectsLayer(template: t, match: widget.match, version: widget.version),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Changes only when an owner, value or base changes: the ownership layer repaints then.
  String _ownerKey() {
    final b = StringBuffer();
    for (final e in widget.match.territories.entries) {
      b
        ..write(e.key)
        ..write(':')
        ..write(e.value.owner)
        ..write(e.value.isBase ? 'b' : '')
        ..write(';');
    }
    return b.toString();
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
    final fs = max(9.0, size.height * 0.026);
    for (final shape in widget.template.territories) {
      final terr = m.territories[shape.id];
      if (terr == null || terr.owner == null) continue;
      yield Positioned(
        left: shape.label.dx * size.width - 50,
        top: shape.label.dy * size.height + (terr.isBase ? fs * 0.2 : -fs * 1.0),
        width: 100,
        child: IgnorePointer(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueBanner(value: terr.value, color: AppColors.seat(terr.owner), fontSize: fs, shielded: terr.shielded),
              if (terr.isBase) _Towers(count: terr.towers, size: fs * 1.05),
            ],
          ),
        ),
      );
    }
  }
}

/// A small swallow-tailed cloth banner in the owner's colour carrying the territory value.
class ValueBanner extends StatelessWidget {
  const ValueBanner({
    super.key,
    required this.value,
    required this.color,
    required this.fontSize,
    this.shielded = false,
  });
  final int value;
  final Color color;
  final double fontSize;
  final bool shielded;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BannerPainter(color),
      child: Padding(
        padding: EdgeInsets.fromLTRB(fontSize * 0.55, fontSize * 0.05, fontSize * 0.55, fontSize * 0.42),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (shielded) Icon(Icons.shield, size: fontSize * 0.9, color: const Color(0xFFFFE08A)),
            Text(
              '$value',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.25,
                shadows: const [Shadow(color: Color(0xCC000000), offset: Offset(0, 1), blurRadius: 1)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerPainter extends CustomPainter {
  _BannerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, notch = h * 0.28;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h - notch)
      ..lineTo(0, h)
      ..close();
    final hsl = HSLColor.fromColor(color);
    canvas.drawPath(path.shift(const Offset(0, 1.5)), Paint()..color = const Color(0x66000000));
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            hsl.withLightness((hsl.lightness + 0.08).clamp(0, 1)).toColor(),
            hsl.withLightness(hsl.lightness * 0.7).toColor(),
          ],
        ).createShader(Offset.zero & size),
    );
    // gold pole on top and an ink edge
    canvas.drawLine(
      const Offset(-2, 0.8),
      Offset(w + 2, 0.8),
      Paint()
        ..color = const Color(0xFFE2B85A)
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xAA1A0F06),
    );
  }

  @override
  bool shouldRepaint(_BannerPainter old) => old.color != color;
}

/// One tower drawing and the count, instead of a row of emoji.
class _Towers extends StatelessWidget {
  const _Towers({required this.count, required this.size});
  final int count;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 2),
      padding: EdgeInsets.symmetric(horizontal: size * 0.3),
      decoration: BoxDecoration(
        color: const Color(0xDD2B1D0F),
        borderRadius: BorderRadius.circular(size),
        border: Border.all(color: const Color(0xFFD4A64A), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.castle, size: size, color: count > 0 ? const Color(0xFFE9D6AC) : AppColors.bad),
          Text(
            ' ×$count',
            style: TextStyle(
              fontSize: size * 0.8,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Seat colour wash: soft in the middle, strong at the edge (ink-wash look), ink border on top.
class _OwnershipPainter extends CustomPainter {
  _OwnershipPainter({required this.template, required this.match, required this.key});
  final MapTemplate template;
  final MatchView match;
  final String key;

  @override
  void paint(Canvas canvas, Size size) {
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

    final fill = Paint()..style = PaintingStyle.fill;
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = size.height * 0.028;
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    for (final shape in template.territories) {
      final path = shape.path(size);
      final owner = match.territories[shape.id]?.owner;
      if (owner == null) continue;
      final c = AppColors.seat(owner);
      fill.color = c.withValues(alpha: 0.30);
      canvas.drawPath(path, fill);
      canvas.save();
      canvas.clipPath(path);
      edge.color = c.withValues(alpha: 0.55);
      canvas.drawPath(path, edge);
      canvas.restore();
    }
    // borders after all fills, so neighbours do not paint over each other's ink
    for (final shape in template.territories) {
      final path = shape.path(size);
      final owner = match.territories[shape.id]?.owner;
      ink
        ..color = owner == null ? const Color(0x55392A18) : const Color(0xE01A0F06)
        ..strokeWidth = size.height * (owner == null ? 0.002 : 0.005);
      canvas.drawPath(path, ink);
      if (owner != null) {
        ink
          ..color = AppColors.seat(owner)
          ..strokeWidth = size.height * 0.0022;
        canvas.drawPath(path, ink);
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
  bool shouldRepaint(_OwnershipPainter old) => old.key != key || old.template != template;
}

/// Legal choices: everything else dims, choices get gold marching-ants borders.
class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.template,
    required this.highlight,
    required this.selected,
    required this.duel,
    required this.t,
  });
  final MapTemplate template;
  final Set<int> highlight;
  final Set<int> selected;
  final int? duel;
  final double t; // 0..1, repeating

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = 0.5 + 0.5 * sin(t * 2 * pi);
    if (highlight.isNotEmpty) {
      final dim = Paint()..color = const Color(0x40000000);
      for (final s in template.territories) {
        if (!highlight.contains(s.id) && !selected.contains(s.id)) canvas.drawPath(s.path(size), dim);
      }
    }
    final glow = Paint()..style = PaintingStyle.fill;
    final ants = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.height * 0.006
      ..color = AppColors.gold
      ..strokeCap = StrokeCap.round;
    for (final id in highlight) {
      final path = template.byId(id).path(size);
      glow.color = AppColors.gold.withValues(alpha: 0.10 + 0.16 * pulse);
      canvas.drawPath(path, glow);
      _ants(canvas, path, ants, size.height * 0.018, t);
    }
    for (final id in selected) {
      glow.color = AppColors.gold.withValues(alpha: 0.5);
      canvas.drawPath(template.byId(id).path(size), glow);
    }
    if (duel != null) {
      final path = template.byId(duel!).path(size);
      glow.color = Colors.white.withValues(alpha: 0.10 + 0.22 * pulse);
      canvas.drawPath(path, glow);
      _ants(
        canvas,
        path,
        ants
          ..color = const Color(0xFFFFF1D0)
          ..strokeWidth = size.height * 0.007,
        size.height * 0.022,
        t,
      );
    }
  }

  void _ants(Canvas c, Path path, Paint p, double dash, double t) {
    for (final metric in path.computeMetrics()) {
      for (var d = (t * dash * 2) % (dash * 2) - dash * 2; d < metric.length; d += dash * 2) {
        final a = max(0.0, d), b = min(metric.length, d + dash);
        if (b > a) c.drawPath(metric.extractPath(a, b), p);
      }
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter old) => true;
}

// ---------------------------------------------------------------------------------- effects

const _fxLength = {
  'march': Duration(milliseconds: 1500),
  'capture': Duration(milliseconds: 1800),
  'held': Duration(milliseconds: 1300),
  'tower': Duration(milliseconds: 1300),
  'claim': Duration(milliseconds: 900),
};

/// Runs a ticker only while some effect is still playing.
class _EffectsLayer extends StatefulWidget {
  const _EffectsLayer({required this.template, required this.match, required this.version});
  final MapTemplate template;
  final MatchView match;
  final int version;

  @override
  State<_EffectsLayer> createState() => _EffectsLayerState();
}

class _EffectsLayerState extends State<_EffectsLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {
    if (_live().isEmpty) _ticker.stop();
    setState(() {});
  });

  List<Fx> _live() {
    final now = DateTime.now();
    return [
      for (final f in widget.match.fx)
        if (now.difference(f.at) < (_fxLength[f.kind] ?? Duration.zero)) f,
    ];
  }

  @override
  void didUpdateWidget(_EffectsLayer old) {
    super.didUpdateWidget(old);
    if (!_ticker.isActive && _live().isNotEmpty) _ticker.start();
  }

  @override
  void initState() {
    super.initState();
    if (_live().isNotEmpty) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = _live();
    if (live.isEmpty) return const SizedBox.expand();
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _EffectsPainter(template: widget.template, match: widget.match, fx: live, now: DateTime.now()),
      ),
    );
  }
}

class _EffectsPainter extends CustomPainter {
  _EffectsPainter({required this.template, required this.match, required this.fx, required this.now});
  final MapTemplate template;
  final MatchView match;
  final List<Fx> fx;
  final DateTime now;

  Offset _at(int id, Size s) {
    final l = template.byId(id).label;
    return Offset(l.dx * s.width, l.dy * s.height);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final f in fx) {
      final total = _fxLength[f.kind]!.inMilliseconds;
      final p = (now.difference(f.at).inMilliseconds / total).clamp(0.0, 1.0);
      final color = AppColors.seat(f.seat);
      switch (f.kind) {
        case 'march':
          _march(canvas, size, f, p, color);
        case 'capture':
          _capture(canvas, size, f, p, color);
        case 'held':
          _held(canvas, size, f, p);
        case 'tower':
          _tower(canvas, size, f, p);
        case 'claim':
          _flag(canvas, _at(f.territory, size), size.height * 0.07, Curves.elasticOut.transform(p), color, 1 - p * 0.3);
      }
    }
  }

  /// The attacker's closest territory to the target (a neighbour when there is one).
  Offset? _from(Fx f, Size size) {
    final seat = f.seat;
    if (seat == null) return null;
    final target = template.byId(f.territory);
    final mine = [
      for (final e in match.territories.entries)
        if (e.value.owner == seat && e.key != f.territory) e.key,
    ];
    if (mine.isEmpty) return null;
    final near = mine.where(target.neighbors.contains).toList();
    final pool = near.isEmpty ? mine : near;
    final to = _at(f.territory, size);
    pool.sort((a, b) => (_at(a, size) - to).distance.compareTo((_at(b, size) - to).distance));
    return _at(pool.first, size);
  }

  void _march(Canvas canvas, Size size, Fx f, double p, Color color) {
    final from = _from(f, size);
    if (from == null) return;
    final to = _at(f.territory, size);
    final mid = (from + to) / 2;
    final normal = Offset(-(to - from).dy, (to - from).dx) * 0.25;
    final ctrl = mid + normal;
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(ctrl.dx, ctrl.dy, to.dx, to.dy);
    final metric = path.computeMetrics().first;
    final grow = Curves.easeOutCubic.transform((p / 0.6).clamp(0.0, 1.0));
    final fade = p < 0.75 ? 1.0 : 1 - (p - 0.75) / 0.25;
    final len = metric.length * grow;
    final w = size.height * 0.012;
    final dashLen = w * 2.2;
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * 1.7
      ..color = const Color(0xFF1A0F06).withValues(alpha: 0.8 * fade);
    final body = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w
      ..color = color.withValues(alpha: fade);
    for (var d = 0.0; d < len - w * 3; d += dashLen * 1.6) {
      final seg = metric.extractPath(d, min(d + dashLen, len));
      canvas.drawPath(seg, ink);
      canvas.drawPath(seg, body);
    }
    final tan = metric.getTangentForOffset(max(1, len));
    if (tan != null) {
      final a = tan.position, dir = tan.vector / tan.vector.distance;
      final side = Offset(-dir.dy, dir.dx);
      final head = Path()
        ..moveTo(a.dx + dir.dx * w * 1.5, a.dy + dir.dy * w * 1.5)
        ..lineTo(a.dx - dir.dx * w * 3 + side.dx * w * 2.2, a.dy - dir.dy * w * 3 + side.dy * w * 2.2)
        ..lineTo(a.dx - dir.dx * w * 3 - side.dx * w * 2.2, a.dy - dir.dy * w * 3 - side.dy * w * 2.2)
        ..close();
      canvas.drawPath(head, Paint()..color = const Color(0xFF1A0F06).withValues(alpha: fade));
      canvas.drawPath(head.shift(Offset.zero), body..style = PaintingStyle.fill);
    }
    // crossed swords over the target once the arrow lands
    if (p > 0.55) {
      final s = Curves.elasticOut.transform(((p - 0.55) / 0.45).clamp(0.0, 1.0));
      _swords(canvas, to - Offset(0, size.height * 0.06), size.height * 0.05 * s, fade);
    }
  }

  void _swords(Canvas canvas, Offset c, double r, double alpha) {
    if (r <= 0) return;
    final blade = Paint()
      ..strokeWidth = r * 0.22
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE8E8E8).withValues(alpha: alpha);
    final edge = Paint()
      ..strokeWidth = r * 0.36
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF1A0F06).withValues(alpha: alpha);
    final hilt = Paint()
      ..strokeWidth = r * 0.26
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFD4A64A).withValues(alpha: alpha);
    for (final s in [1.0, -1.0]) {
      final a = c + Offset(-r * s, r), b = c + Offset(r * s, -r);
      canvas.drawLine(a, b, edge);
      canvas.drawLine(a, b, blade);
      final g = c + Offset(-r * s * 0.55, r * 0.55);
      canvas.drawLine(g + Offset(-r * 0.3, -r * 0.3 * s), g + Offset(r * 0.3, r * 0.3 * s), hilt);
    }
  }

  void _capture(Canvas canvas, Size size, Fx f, double p, Color color) {
    final shape = template.byId(f.territory);
    final path = shape.path(size);
    final c = _at(f.territory, size);
    // colour spreads out from the flag
    final bounds = path.getBounds();
    final maxR = max(bounds.width, bounds.height);
    final spread = Curves.easeOutQuad.transform((p / 0.7).clamp(0.0, 1.0));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(c, maxR * spread, Paint()..color = color.withValues(alpha: 0.5 * (1 - p)));
    canvas.drawCircle(
      c,
      maxR * spread,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.01
        ..color = Colors.white.withValues(alpha: 0.6 * (1 - spread)),
    );
    canvas.restore();
    // the flag is driven into the ground
    final plant = Curves.elasticOut.transform((p / 0.5).clamp(0.0, 1.0));
    final fade = p < 0.8 ? 1.0 : 1 - (p - 0.8) / 0.2;
    _flag(canvas, c, size.height * 0.09, plant, color, fade, wave: p * 12);
    // the value floats up
    _floatText(canvas, '+${f.value}', c - Offset(0, size.height * (0.09 + 0.06 * p)), size.height * 0.04, color, fade);
  }

  void _flag(Canvas canvas, Offset base, double h, double s, Color color, double alpha, {double wave = 0}) {
    if (s <= 0 || alpha <= 0) return;
    final top = base - Offset(0, h * s);
    canvas.drawLine(
      base,
      top,
      Paint()
        ..strokeWidth = h * 0.07
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF3B2610).withValues(alpha: alpha),
    );
    canvas.drawCircle(top, h * 0.06, Paint()..color = const Color(0xFFE2B85A).withValues(alpha: alpha));
    final w = h * 0.62 * s, fh = h * 0.38 * s;
    final y0 = top.dy + h * 0.04;
    final cloth = Path()..moveTo(top.dx, y0);
    for (var i = 1; i <= 8; i++) {
      final x = top.dx - w * i / 8; // RTL map: the flag flies to the left
      cloth.lineTo(x, y0 + sin(wave + i * 0.8) * fh * 0.08 * i / 8);
    }
    cloth.lineTo(top.dx - w * 0.85, y0 + fh * 0.5);
    for (var i = 8; i >= 0; i--) {
      final x = top.dx - w * i / 8;
      cloth.lineTo(x, y0 + fh + sin(wave + i * 0.8) * fh * 0.08 * i / 8);
    }
    cloth.close();
    canvas.drawPath(cloth, Paint()..color = color.withValues(alpha: alpha));
    canvas.drawPath(
      cloth,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFF1A0F06).withValues(alpha: alpha * 0.8),
    );
  }

  void _held(Canvas canvas, Size size, Fx f, double p) {
    final c = _at(f.territory, size) - Offset(0, size.height * 0.05);
    final r = size.height * 0.05 * (1 + 0.25 * sin(p * pi));
    final fade = 1 - p;
    final shield = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx + r * 0.9, c.dy - r * 0.9, c.dx + r * 0.85, c.dy - r * 0.3)
      ..quadraticBezierTo(c.dx + r * 0.7, c.dy + r * 0.6, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx - r * 0.7, c.dy + r * 0.6, c.dx - r * 0.85, c.dy - r * 0.3)
      ..quadraticBezierTo(c.dx - r * 0.9, c.dy - r * 0.9, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(shield, Paint()..color = AppColors.seat(f.seat).withValues(alpha: 0.9 * fade));
    canvas.drawPath(
      shield,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.14
        ..color = const Color(0xFFE2B85A).withValues(alpha: fade),
    );
    // a glint sweeping across
    final gx = c.dx - r + 2 * r * p;
    canvas.save();
    canvas.clipPath(shield);
    canvas.drawLine(
      Offset(gx - r * 0.3, c.dy - r),
      Offset(gx + r * 0.3, c.dy + r),
      Paint()
        ..strokeWidth = r * 0.25
        ..color = Colors.white.withValues(alpha: 0.7 * fade),
    );
    canvas.restore();
    // the territory's edge flashes white
    canvas.drawPath(
      template.byId(f.territory).path(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.height * 0.008
        ..color = Colors.white.withValues(alpha: 0.7 * fade),
    );
  }

  void _tower(Canvas canvas, Size size, Fx f, double p) {
    final c = _at(f.territory, size) + Offset(0, size.height * 0.035);
    final h = size.height * 0.05;
    // the tower drops and tilts
    final fall = Curves.easeIn.transform(p);
    canvas.save();
    canvas.translate(c.dx + sin(p * 40) * h * 0.08 * (1 - p), c.dy - h + fall * h * 0.9);
    canvas.rotate(fall * 0.5);
    final body = Paint()..color = const Color(0xFF9C8B6E).withValues(alpha: 1 - fall * 0.7);
    canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: h * 0.55, height: h), body);
    for (var i = -1; i <= 1; i++) {
      canvas.drawRect(Rect.fromCenter(center: Offset(i * h * 0.2, -h * 0.58), width: h * 0.14, height: h * 0.18), body);
    }
    canvas.restore();
    // dust
    final r = Random(f.territory * 31 + f.at.millisecond);
    final dust = Paint();
    for (var i = 0; i < 14; i++) {
      final ang = r.nextDouble() * pi; // upward half
      final dist = h * (0.4 + r.nextDouble() * 1.4) * Curves.easeOut.transform(p);
      final o = c + Offset(cos(ang) * dist * (r.nextBool() ? 1 : -1), -sin(ang) * dist * 0.6);
      dust.color = const Color(0xFF8A7556).withValues(alpha: 0.55 * (1 - p));
      canvas.drawCircle(o, h * (0.12 + 0.25 * p) * (0.6 + r.nextDouble() * 0.6), dust);
    }
    _floatText(canvas, '−1', c - Offset(0, h * (1.6 + p)), h * 0.75, AppColors.bad, 1 - p);
  }

  void _floatText(Canvas canvas, String text, Offset at, double fs, Color color, double alpha) {
    if (alpha <= 0) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: fs,
          fontWeight: FontWeight.w900,
          foreground: Paint()..color = Colors.white.withValues(alpha: alpha),
          shadows: [
            Shadow(
              color: color.withValues(alpha: alpha),
              blurRadius: 0,
              offset: const Offset(0, 2),
            ),
            Shadow(color: const Color(0xFF000000).withValues(alpha: alpha), blurRadius: 3),
          ],
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_EffectsPainter old) => true;
}
