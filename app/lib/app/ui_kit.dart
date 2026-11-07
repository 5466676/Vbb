import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Game-styled building blocks: wax-seal and wood buttons, parchment and wood panels,
/// a Ruqaa heading. Everything is painted with gradients and paths (no blur, no images),
/// so it stays cheap on low-end phones.

/// Calligraphic heading (Aref Ruqaa) with a dark ink outline so it reads on any background.
class RuqaaTitle extends StatelessWidget {
  const RuqaaTitle(this.text, {super.key, this.size = 34, this.color = AppColors.gold, this.outline = true});
  final String text;
  final double size;
  final Color color;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppTheme.headingFont,
      fontSize: size,
      height: 1.25,
      fontWeight: FontWeight.w700,
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        if (outline)
          Text(
            text,
            textAlign: TextAlign.center,
            style: style.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = size * 0.12
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xFF1A0F06),
            ),
          ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: style.copyWith(color: color),
        ),
      ],
    );
  }
}

enum WarButtonKind { seal, wood, parchment }

/// The main button of the game. `seal`: red wax with a brass rim (main action).
/// `wood`: dark walnut with a brass rim. `parchment`: light, for use on dark wood.
class WarButton extends StatefulWidget {
  const WarButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = WarButtonKind.wood,
    this.icon,
    this.height = 50,
    this.fontSize,
  });

  final String label;
  final VoidCallback? onPressed;
  final WarButtonKind kind;
  final IconData? icon;
  final double height;
  final double? fontSize;

  @override
  State<WarButton> createState() => _WarButtonState();
}

class _WarButtonState extends State<WarButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final (top, bottom, fg) = switch (widget.kind) {
      WarButtonKind.seal => (const Color(0xFFC0392B), const Color(0xFF6E1A12), const Color(0xFFFBE9C6)),
      WarButtonKind.wood => (const Color(0xFF5A3D22), const Color(0xFF2E1D0F), AppColors.textPrimary),
      WarButtonKind.parchment => (const Color(0xFFF6EAD0), const Color(0xFFD8C39A), AppColors.ink),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: enabled
              ? (_) {
                  setState(() => _down = false);
                  widget.onPressed!();
                }
              : null,
          child: AnimatedScale(
            scale: _down ? 0.96 : 1,
            duration: const Duration(milliseconds: 80),
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF0CF7A), Color(0xFF9C6B22), Color(0xFFE2B85A), Color(0xFF7A4E15)],
                  stops: [0, 0.45, 0.6, 1],
                ),
                boxShadow: const [BoxShadow(color: Color(0x99000000), offset: Offset(0, 3), blurRadius: 3)],
              ),
              padding: const EdgeInsets.all(2.2), // brass rim
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: _down ? [bottom, top] : [top, bottom],
                  ),
                ),
                child: CustomPaint(
                  painter: _GrainPainter(widget.kind),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, color: fg, size: (widget.fontSize ?? 17) + 3),
                              if (widget.label.isNotEmpty) const SizedBox(width: 8),
                            ],
                            if (widget.label.isNotEmpty)
                              Text(
                                widget.label,
                                style: TextStyle(
                                  color: fg,
                                  fontSize: widget.fontSize ?? (widget.kind == WarButtonKind.seal ? 19 : 17),
                                  fontWeight: FontWeight.w800,
                                  shadows: [
                                    Shadow(
                                      color: widget.kind == WarButtonKind.parchment
                                          ? const Color(0x66FFFFFF)
                                          : const Color(0xAA000000),
                                      offset: const Offset(0, 1.5),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faint wood grain or wax swirl lines, painted once (cached by the raster cache).
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.kind);
  final WarButtonKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = kind == WarButtonKind.parchment ? const Color(0x14513A1C) : const Color(0x1AFFFFFF);
    final r = Random(size.width.toInt() ^ kind.index);
    for (var i = 0; i < 5; i++) {
      final y = size.height * (0.15 + 0.17 * i) + r.nextDouble() * 3;
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += size.width / 6) {
        path.quadraticBezierTo(x + size.width / 12, y + (r.nextDouble() - 0.5) * 5, x + size.width / 6, y);
      }
      canvas.drawPath(path, p);
    }
    // top highlight
    canvas.drawLine(
      const Offset(6, 1.5),
      Offset(size.width - 6, 1.5),
      Paint()
        ..color = const Color(0x40FFFFFF)
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.kind != kind;
}

/// A dark wood board with a brass frame and corner studs — menus and dialogs sit on it.
class WoodPanel extends StatelessWidget {
  const WoodPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.width});
  final Widget child;
  final EdgeInsets padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(colors: [Color(0xFFB8893A), Color(0xFF6B4614), Color(0xFFD9AE5C)]),
        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(3),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xF23A2715), Color(0xF2241709), Color(0xF2342211)],
          ),
        ),
        child: CustomPaint(
          foregroundPainter: _StudsPainter(),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class _StudsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x55D4A64A);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(5, 5, size.width - 10, size.height - 10), const Radius.circular(5)),
      inner,
    );
    final stud = Paint()
      ..shader = const RadialGradient(colors: [Color(0xFFFFE6A3), Color(0xFF8A5A17)])
          .createShader(Rect.fromCircle(center: Offset.zero, radius: 4));
    for (final c in [
      const Offset(10, 10),
      Offset(size.width - 10, 10),
      Offset(10, size.height - 10),
      Offset(size.width - 10, size.height - 10),
    ]) {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.drawCircle(Offset.zero, 3.6, stud);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_StudsPainter old) => false;
}

/// A parchment sheet with an ink double border and corner flourishes.
class ParchmentPanel extends StatelessWidget {
  const ParchmentPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const RadialGradient(
          radius: 1.1,
          colors: [Color(0xFFF7ECD2), Color(0xFFE9D6AC), Color(0xFFCDAF78)],
          stops: [0, 0.7, 1],
        ),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: CustomPaint(
        foregroundPainter: _InkFramePainter(),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _InkFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()
      ..style = PaintingStyle.stroke
      ..color = const Color(0xAA4A3418);
    ink.strokeWidth = 1.6;
    canvas.drawRect(Rect.fromLTWH(5, 5, size.width - 10, size.height - 10), ink);
    ink.strokeWidth = 0.8;
    canvas.drawRect(Rect.fromLTWH(9, 9, size.width - 18, size.height - 18), ink);
    // corner diamonds
    final fill = Paint()..color = const Color(0xCC7A2A18);
    for (final c in [
      const Offset(9, 9),
      Offset(size.width - 9, 9),
      Offset(9, size.height - 9),
      Offset(size.width - 9, size.height - 9),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy - 5)
          ..lineTo(c.dx + 5, c.dy)
          ..lineTo(c.dx, c.dy + 5)
          ..lineTo(c.dx - 5, c.dy)
          ..close(),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_InkFramePainter old) => false;
}

/// A pick-one row of banner-shaped choices (difficulty, map, count…).
class BannerChoice<T> extends StatelessWidget {
  const BannerChoice({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in options)
          SizedBox(
            width: 96,
            height: 40,
            child: WarButton(
              label: o.$2,
              height: 40,
              fontSize: 15,
              kind: o.$1 == value ? WarButtonKind.seal : WarButtonKind.wood,
              onPressed: () => onChanged(o.$1),
            ),
          ),
      ],
    );
  }
}
