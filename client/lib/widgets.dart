import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'theme.dart';

/// ---------- Logo (drawn in code, no image files needed) ----------
class LogoPainter extends CustomPainter {
  LogoPainter({this.angle = 0.6});
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final orbit = r * 0.62;
    final rect = Rect.fromCircle(center: c, radius: orbit);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.12
      ..shader = const SweepGradient(
        colors: [AppColors.violet, AppColors.mint, AppColors.violet],
      ).createShader(rect);
    canvas.drawCircle(c, orbit, ring);

    canvas.drawCircle(
      c,
      r * 0.26,
      Paint()
        ..shader = AppColors.cta
            .createShader(Rect.fromCircle(center: c, radius: r * 0.26)),
    );

    final p1 = c + Offset(cos(angle), sin(angle)) * orbit;
    final p2 = c + Offset(cos(angle + pi), sin(angle + pi)) * orbit;
    canvas.drawCircle(p1, r * 0.2, Paint()..color = AppColors.bg);
    canvas.drawCircle(p1, r * 0.15, Paint()..color = AppColors.lime);
    canvas.drawCircle(p2, r * 0.2, Paint()..color = AppColors.bg);
    canvas.drawCircle(p2, r * 0.15, Paint()..color = AppColors.pink);
  }

  @override
  bool shouldRepaint(LogoPainter old) => old.angle != angle;
}

class OrbytLogo extends StatelessWidget {
  const OrbytLogo({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: LogoPainter());
}

class AnimatedOrbit extends StatefulWidget {
  const AnimatedOrbit({super.key, this.size = 120});
  final double size;
  @override
  State<AnimatedOrbit> createState() => _AnimatedOrbitState();
}

class _AnimatedOrbitState extends State<AnimatedOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 3))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.square(widget.size),
          painter: LogoPainter(angle: _c.value * 2 * pi),
        ),
      );
}

/// ---------- Animated aurora + dot grid background ----------
class _DotGrid extends CustomPainter {
  const _DotGrid();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withOpacity(0.05);
    const gap = 32.0;
    for (double x = gap / 2; x < size.width; x += gap) {
      for (double y = gap / 2; y < size.height; y += gap) {
        canvas.drawCircle(Offset(x, y), 1, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGrid old) => false;
}

class AuroraBackground extends StatefulWidget {
  const AuroraBackground({super.key, required this.child});
  final Widget child;
  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 28))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _blob(Alignment a, Color color, double opacity, double size) => Align(
        alignment: a,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withOpacity(opacity),
              color.withOpacity(0),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        final t = _c.value * 2 * pi;
        return Stack(children: [
          Positioned.fill(child: Container(color: AppColors.bg)),
          Positioned.fill(
              child: _blob(Alignment(-0.95 + 0.3 * sin(t), -0.85 + 0.2 * cos(t)),
                  AppColors.violet, 0.5, 780)),
          Positioned.fill(
              child: _blob(Alignment(0.95 + 0.2 * cos(t), 0.55 + 0.25 * sin(t)),
                  AppColors.mint, 0.2, 720)),
          Positioned.fill(
              child: _blob(Alignment(0.2 * sin(t * 2), 1.15 + 0.1 * cos(t)),
                  AppColors.pink, 0.2, 640)),
          const Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _DotGrid(), size: Size.infinite),
              ),
            ),
          ),
          Positioned.fill(child: child!),
        ]);
      },
    );
  }
}

/// ---------- Glass card ----------
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 28,
    this.glow,
  });
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: glow == null
            ? null
            : [
                BoxShadow(
                    color: glow!.withOpacity(0.18),
                    blurRadius: 40,
                    spreadRadius: -8),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withOpacity(0.09),
                  Colors.white.withOpacity(0.035),
                ],
              ),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: Colors.white.withOpacity(0.11)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// ---------- Small status pill ----------
class Pill extends StatelessWidget {
  const Pill({super.key, required this.child, this.highlight = false});
  final Widget child;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.lime.withOpacity(0.12)
            : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
            color: highlight
                ? AppColors.lime.withOpacity(0.4)
                : Colors.white.withOpacity(0.12)),
      ),
      child: child,
    );
  }
}

/// ---------- Primary (lime -> mint) button ----------
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.height = 52,
  });
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height / 2);
    return Opacity(
      opacity: onPressed == null ? 0.5 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.cta,
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: AppColors.lime.withOpacity(0.32),
              blurRadius: 24,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26),
              child: SizedBox(
                height: height,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 20, color: AppColors.onCta),
                      const SizedBox(width: 8),
                    ],
                    Text(label,
                        style: display(
                            size: 15,
                            weight: FontWeight.w700,
                            color: AppColors.onCta)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------- Round icon button ----------
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.active = true,
    this.danger = false,
    this.size = 48,
  });
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final bool danger;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? const Color(0xFFEF4444).withOpacity(0.9)
        : (active
            ? Colors.white.withOpacity(0.12)
            : Colors.white.withOpacity(0.04));
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon,
                size: size * 0.46,
                color: onPressed == null
                    ? Colors.white30
                    : (active ? Colors.white : Colors.white54)),
          ),
        ),
      ),
    );
  }
}
