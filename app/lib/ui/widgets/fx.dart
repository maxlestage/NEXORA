import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Un fond animé : trois halos colorés qui dérivent lentement.
class Aurora extends StatefulWidget {
  const Aurora({super.key, this.child, this.intensity = 1});

  final Widget? child;
  final double intensity;

  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (Nx.animationsOff) {
      if (_c.isAnimating) _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
    final pal =
        Theme.of(context).extension<NxPalette>()?.colors ??
        const [Nx.cyan, Nx.violet, Nx.magenta];
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(
              painter: _AuroraPainter(_c.value, dark, widget.intensity, pal),
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.v, this.dark, this.intensity, this.pal);

  final double v;
  final bool dark;
  final double intensity;
  final List<Color> pal;

  @override
  void paint(Canvas canvas, Size size) {
    final a = v * math.pi * 2;
    final blobs = [
      (pal[1], Offset(0.2 + 0.15 * math.sin(a), 0.15 + 0.1 * math.cos(a))),
      (
        pal[0],
        Offset(0.85 + 0.1 * math.cos(a * 1.3), 0.3 + 0.12 * math.sin(a)),
      ),
      (pal[2], Offset(0.5 + 0.2 * math.sin(a * 0.7), 0.9 + 0.08 * math.cos(a))),
    ];
    for (final (color, pos) in blobs) {
      final center = Offset(pos.dx * size.width, pos.dy * size.height);
      final r = size.shortestSide * 0.75;
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: (dark ? 0.22 : 0.12) * intensity),
              Colors.transparent,
            ],
          ).createShader(Rect.fromCircle(center: center, radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.v != v || old.dark != dark || old.pal != pal;
}

/// Un texte rempli du dégradé NEXORA.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (r) => Nx.gradientOf(context).createShader(r),
      blendMode: BlendMode.srcIn,
      child: Text(text, style: style),
    );
  }
}

/// Une carte en verre dépoli, avec une bordure lumineuse.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.glow,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? glow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: dark
              ? Colors.white.withValues(alpha: 0.045)
              : Colors.white.withValues(alpha: 0.75),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
            side: BorderSide(
              color: (glow ?? (dark ? Colors.white : Colors.black)).withValues(
                alpha: glow != null ? 0.45 : 0.08,
              ),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radius),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Une carte qui s'incline en 3D sous le doigt et revient en douceur.
class Tilt3D extends StatefulWidget {
  const Tilt3D({super.key, required this.child, this.maxAngle = 0.18});

  final Widget child;
  final double maxAngle;

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> {
  Offset _tilt = Offset.zero;

  void _update(Offset local, Size size) {
    final dx = (local.dx / size.width - 0.5) * 2;
    final dy = (local.dy / size.height - 0.5) * 2;
    setState(() => _tilt = Offset(dx.clamp(-1, 1), dy.clamp(-1, 1)));
  }

  @override
  Widget build(BuildContext context) {
    if (Nx.animationsOff) return widget.child;
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth.isFinite ? c.maxWidth : 300, 200);
        return Listener(
          onPointerDown: (e) => _update(e.localPosition, size),
          onPointerMove: (e) => _update(e.localPosition, size),
          onPointerUp: (_) => setState(() => _tilt = Offset.zero),
          onPointerCancel: (_) => setState(() => _tilt = Offset.zero),
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(end: _tilt),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            builder: (context, t, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateX(-t.dy * widget.maxAngle)
                ..rotateY(t.dx * widget.maxAngle),
              child: child,
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

/// Fait apparaître un enfant en glissant, avec un délai (listes en cascade).
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.index = 0, this.dy = 24});

  final Widget child;
  final int index;
  final double dy;

  @override
  Widget build(BuildContext context) {
    if (Nx.animationsOff) return child;
    final delay = (index.clamp(0, 12)) * 45;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 420 + delay),
      curve: Interval(delay / (420 + delay), 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * dy),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX((1 - v) * 0.35),
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Un petit badge (« gratuit », « local »…).
class Badge2 extends StatelessWidget {
  const Badge2(this.label, {super.key, this.color = Nx.green, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Une pastille ronde avec un emoji, sur fond coloré.
class EmojiAvatar extends StatelessWidget {
  const EmojiAvatar(
    this.emoji, {
    super.key,
    this.color = Nx.violet,
    this.size = 44,
  });

  final String emoji;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.45),
            color.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.48)),
    );
  }
}

/// Un en-tête de section.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Un état vide, avec une illustration.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
    this.action,
  });

  final Widget icon;
  final String title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: tt.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

void toast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Nx.red.withValues(alpha: 0.95) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
}

Future<void> copyText(
  BuildContext context,
  String text, {
  String message = 'Copié',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.selectionClick();
  if (context.mounted) toast(context, message);
}
