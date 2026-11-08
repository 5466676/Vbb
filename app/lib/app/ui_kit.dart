import 'package:flutter/material.dart';

import '../core/ranks.dart';
import 'theme.dart';

/// Game-styled building blocks in the neon «system window» look: glowing-edge buttons and
/// panels, a glowing heading. Painted with gradients and box shadows (no blur filters, no images),
/// so it stays cheap on low-end phones.

/// Heading with a neon glow (kept the old name; the text is Cairo Black now, which reads like
/// a system notice).
class RuqaaTitle extends StatelessWidget {
  const RuqaaTitle(this.text, {super.key, this.size = 34, this.color = AppColors.neon, this.outline = true});
  final String text;
  final double size;
  final Color color;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: size * 0.8,
        height: 1.3,
        fontWeight: FontWeight.w900,
        color: Color.lerp(color, Colors.white, 0.35),
        shadows: outline
            ? [
                Shadow(color: color, blurRadius: size * 0.35),
                Shadow(color: color.withValues(alpha: 0.6), blurRadius: 2),
              ]
            : null,
      ),
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
    // seal: the main action, a lit cyan slab. wood: a dark navy key with a cyan edge.
    // parchment: the same with a violet edge, for secondary choices.
    final (top, bottom, fg, edge) = switch (widget.kind) {
      WarButtonKind.seal => (const Color(0xFF1C6FA8), const Color(0xFF0B3A66), Colors.white, AppColors.neon),
      WarButtonKind.wood => (const Color(0xFF10234A), const Color(0xFF081430), AppColors.textPrimary, AppColors.neon),
      WarButtonKind.parchment => (
        const Color(0xFF1B1446),
        const Color(0xFF0E0B2A),
        AppColors.textPrimary,
        AppColors.violet,
      ),
    };
    final lit = widget.kind == WarButtonKind.seal;
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
                borderRadius: BorderRadius.circular(6),
                color: edge,
                boxShadow: AppColors.glow(edge, blur: lit || _down ? 14 : 8, alpha: lit ? 0.75 : 0.45),
              ),
              padding: const EdgeInsets.all(1.6), // neon edge
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
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
                                  shadows: [Shadow(color: edge.withValues(alpha: 0.8), blurRadius: lit ? 8 : 4)],
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

/// Faint scanlines and corner ticks, painted once (cached by the raster cache).
class _GrainPainter extends CustomPainter {
  _GrainPainter(this.kind);
  final WarButtonKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x0DFFFFFF);
    for (var y = 3.0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
    canvas.drawLine(
      const Offset(4, 1.2),
      Offset(size.width - 4, 1.2),
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = 1,
    );
    final tick = Paint()
      ..color = kind == WarButtonKind.parchment ? AppColors.violet : AppColors.neon
      ..strokeWidth = 2;
    const k = 6.0;
    canvas.drawLine(Offset(size.width - k - 3, size.height - 3), Offset(size.width - 3, size.height - 3), tick);
    canvas.drawLine(Offset(size.width - 3, size.height - k - 3), Offset(size.width - 3, size.height - 3), tick);
    canvas.drawLine(const Offset(3, 3), const Offset(3 + k, 3), tick);
    canvas.drawLine(const Offset(3, 3), const Offset(3, 3 + k), tick);
  }

  @override
  bool shouldRepaint(_GrainPainter old) => old.kind != kind;
}

/// A «system window» panel — menus and dialogs sit on it (kept the old name).
class WoodPanel extends StatelessWidget {
  const WoodPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.width});
  final Widget child;
  final EdgeInsets padding;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: AppColors.window(fill: const Color(0xEE081430)),
      child: CustomPaint(
        foregroundPainter: _CornersPainter(AppColors.neon),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Bright L-shaped corner brackets, the signature of the system windows.
class _CornersPainter extends CustomPainter {
  _CornersPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.square;
    const k = 12.0, i = 4.0;
    for (final (x, y, dx, dy) in [
      (i, i, 1.0, 1.0),
      (size.width - i, i, -1.0, 1.0),
      (i, size.height - i, 1.0, -1.0),
      (size.width - i, size.height - i, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(x, y), Offset(x + k * dx, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + k * dy), p);
    }
  }

  @override
  bool shouldRepaint(_CornersPainter old) => old.color != color;
}

/// A lighter info window with a violet edge (kept the old name).
class ParchmentPanel extends StatelessWidget {
  const ParchmentPanel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppColors.window(edge: AppColors.violet, fill: const Color(0xF0100C30)),
      child: CustomPaint(
        foregroundPainter: _CornersPainter(AppColors.violet),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
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

/// The frame for secondary screens (settings, training, leaderboard): a painted background,
/// a wooden header with a Ruqaa title and a round back button, content on a wood board.
class GameScaffold extends StatelessWidget {
  const GameScaffold({
    super.key,
    required this.title,
    required this.child,
    this.background = 'assets/ui/menu/menu_2.webp',
  });
  final String title;
  final Widget child;
  final String background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(background),
            fit: BoxFit.cover,
            colorFilter: const ColorFilter.mode(Color(0xD905070F), BlendMode.srcATop),
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                height: 56,
                margin: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: AppColors.window(radius: 6, fill: const Color(0xEE081430)),
                child: Row(
                  children: [
                    Semantics(
                      button: true,
                      label: 'رجوع',
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.panelDeep,
                            border: Border.all(color: AppColors.neon, width: 1.6),
                            boxShadow: AppColors.glow(AppColors.neon, blur: 8),
                          ),
                          child: const Icon(Icons.arrow_forward, color: AppColors.neon),
                        ),
                      ),
                    ),
                    Expanded(child: RuqaaTitle(title, size: 30)),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

/// A rank letter (E → S) in a small glowing square, in the rank's own colour.
class RankBadge extends StatelessWidget {
  const RankBadge(this.xp, {super.key, this.size = 18});
  final int xp;
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = rankOf(xp);
    final c = rankColor(r);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.panelDeep,
        borderRadius: BorderRadius.circular(size * 0.18),
        border: Border.all(color: c, width: size > 30 ? 2.4 : 1.3),
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: size * 0.4)],
      ),
      child: Text(
        r,
        style: TextStyle(
          color: c,
          fontWeight: FontWeight.w900,
          fontSize: size * 0.62,
          height: 1,
          shadows: [Shadow(color: c, blurRadius: size * 0.3)],
        ),
      ),
    );
  }
}
