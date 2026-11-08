import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;

  _V3 rotY(double a) => _V3(
    x * math.cos(a) + z * math.sin(a),
    y,
    -x * math.sin(a) + z * math.cos(a),
  );
  _V3 rotX(double a) => _V3(
    x,
    y * math.cos(a) - z * math.sin(a),
    y * math.sin(a) + z * math.cos(a),
  );
  _V3 operator *(double k) => _V3(x * k, y * k, z * k);
}

/// Un nœud qui orbite autour du cœur (un fournisseur, un agent…).
class _Sat {
  _Sat(this.radius, this.speed, this.tilt, this.phase, this.slot, this.size);
  final double radius, speed, tilt, phase, size;

  /// Place dans la palette : 0 à 2 jeu de couleurs, 3 vert, 4 ambre.
  final int slot;
}

/// Le logo vivant de NEXORA : un icosaèdre en 3D (projection perspective réelle),
/// une coque de points, des anneaux et des nœuds en orbite reliés au cœur. On le
/// fait tourner du doigt.
class NexusOrb extends StatefulWidget {
  const NexusOrb({
    super.key,
    this.size = 220,
    this.satellites = 14,
    this.interactive = true,
    this.speed = 1,
    this.pulse = false,
  });

  final double size;
  final int satellites;
  final bool interactive;
  final double speed;

  /// Pulsation plus forte (pendant qu'un modèle répond).
  final bool pulse;

  @override
  State<NexusOrb> createState() => _NexusOrbState();
}

class _NexusOrbState extends State<NexusOrb>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  double _yaw = 0, _pitch = -0.35;
  double _vyaw = 0, _vpitch = 0;
  Duration _last = Duration.zero;
  late final List<_Sat> _sats;

  @override
  void initState() {
    super.initState();
    final r = math.Random(7);
    const colors = [0, 1, 2, 3, 4];
    _sats = List.generate(
      widget.satellites,
      (i) => _Sat(
        1.55 + r.nextDouble() * 0.85,
        (0.25 + r.nextDouble() * 0.6) * (r.nextBool() ? 1 : -1),
        (r.nextDouble() - 0.5) * 1.6,
        r.nextDouble() * math.pi * 2,
        colors[i % colors.length],
        2.5 + r.nextDouble() * 3,
      ),
    );
    _ticker = createTicker(_tick)..start();
  }

  void _tick(Duration elapsed) {
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = elapsed;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() {
      final m = Nx.motionSpeed * (reduce ? 0.15 : 1);
      _t += dt * widget.speed * m;
      _yaw += (0.25 * widget.speed * m) * dt + _vyaw * dt;
      _pitch = (_pitch + _vpitch * dt).clamp(-1.2, 1.2);
      _vyaw *= math.pow(0.04, dt).toDouble();
      _vpitch *= math.pow(0.04, dt).toDouble();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Animations coupées : une image fixe ; rétablies : on repart.
    if (Nx.animationsOff && _ticker.isActive && _t > 0) {
      _ticker.stop();
    } else if (!Nx.animationsOff && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
    final pal =
        Theme.of(context).extension<NxPalette>()?.colors ??
        const [Nx.cyan, Nx.violet, Nx.magenta];
    final painter = CustomPaint(
      size: Size.square(widget.size),
      painter: _OrbPainter(_t, _yaw, _pitch, _sats, widget.pulse, [
        pal[0],
        pal[1],
        pal[2],
        Nx.green,
        Nx.amber,
      ]),
    );
    if (!widget.interactive) return RepaintBoundary(child: painter);
    return GestureDetector(
      onPanUpdate: (d) {
        _yaw += d.delta.dx * 0.012;
        _pitch = (_pitch + d.delta.dy * 0.012).clamp(-1.2, 1.2);
      },
      onPanEnd: (d) {
        _vyaw = d.velocity.pixelsPerSecond.dx * 0.006;
        _vpitch = d.velocity.pixelsPerSecond.dy * 0.006;
      },
      child: RepaintBoundary(child: painter),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t, this.yaw, this.pitch, this.sats, this.pulse, this.pal);

  final double t, yaw, pitch;

  /// Jeu de couleurs (0 principale, 1 et 2 dégradé) puis vert et ambre.
  final List<Color> pal;
  Color get c0 => pal[0];
  Color get c1 => pal[1];
  Color get c2 => pal[2];
  final List<_Sat> sats;
  final bool pulse;

  static final List<_V3> _ico = () {
    final p = (1 + math.sqrt(5)) / 2;
    final v = <_V3>[
      _V3(-1, p, 0), _V3(1, p, 0), _V3(-1, -p, 0), _V3(1, -p, 0), //
      _V3(0, -1, p), _V3(0, 1, p), _V3(0, -1, -p), _V3(0, 1, -p),
      _V3(p, 0, -1), _V3(p, 0, 1), _V3(-p, 0, -1), _V3(-p, 0, 1),
    ];
    final n = math.sqrt(1 + p * p);
    return v.map((e) => e * (1 / n)).toList();
  }();

  static final List<(int, int)> _edges = () {
    final out = <(int, int)>[];
    for (var i = 0; i < _ico.length; i++) {
      for (var j = i + 1; j < _ico.length; j++) {
        final a = _ico[i], b = _ico[j];
        final d = math.sqrt(
          math.pow(a.x - b.x, 2) +
              math.pow(a.y - b.y, 2) +
              math.pow(a.z - b.z, 2),
        );
        if (d < 1.1) out.add((i, j));
      }
    }
    return out;
  }();

  static final List<_V3> _shell = () {
    // Une sphère de points (spirale de Fibonacci).
    const n = 90;
    final g = math.pi * (3 - math.sqrt(5));
    return List.generate(n, (i) {
      final y = 1 - (i / (n - 1)) * 2;
      final r = math.sqrt(1 - y * y);
      return _V3(math.cos(g * i) * r, y, math.sin(g * i) * r);
    });
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final scale = size.width * 0.24;
    const cam = 5.0;

    (Offset, double) project(_V3 p) {
      final q = p.rotY(yaw).rotX(pitch);
      final k = cam / (cam - q.z);
      return (c + Offset(q.x * scale * k, q.y * scale * k), q.z);
    }

    // Halo.
    final beat = 1 + math.sin(t * (pulse ? 6 : 2)) * (pulse ? 0.08 : 0.03);
    canvas.drawCircle(
      c,
      size.width * 0.42 * beat,
      Paint()
        ..shader = RadialGradient(
          colors: [
            c1.withValues(alpha: 0.35),
            c0.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: c, radius: size.width * 0.45)),
    );

    // Anneaux inclinés.
    for (var r = 0; r < 2; r++) {
      final path = Path();
      for (var i = 0; i <= 96; i++) {
        final a = i / 96 * math.pi * 2;
        final radius = r == 0 ? 2.05 : 2.45;
        var p = _V3(math.cos(a) * radius, 0, math.sin(a) * radius);
        p = p.rotX(r == 0 ? 1.1 : -0.7).rotY(t * (r == 0 ? 0.3 : -0.2));
        final (o, _) = project(p);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = (r == 0 ? c2 : c0).withValues(alpha: 0.45),
      );
    }

    // Coque de points.
    final shellPaint = Paint();
    for (final s in _shell) {
      final (o, z) = project(s * (1.6 + math.sin(t * 1.3 + s.y * 3) * 0.04));
      shellPaint.color = Colors.white.withValues(
        alpha: 0.12 + (z + 1.6) * 0.12,
      );
      canvas.drawCircle(o, 1.1 + (z + 1.6) * 0.35, shellPaint);
    }

    // Satellites, reliés au cœur.
    final linePaint = Paint()..strokeWidth = 0.8;
    final sorted = <(Offset, double, _Sat)>[];
    for (final s in sats) {
      final a = s.phase + t * s.speed;
      var p = _V3(
        math.cos(a) * s.radius,
        math.sin(t * 0.7 + s.phase) * 0.35,
        math.sin(a) * s.radius,
      );
      p = p.rotX(s.tilt);
      final (o, z) = project(p);
      sorted.add((o, z, s));
    }
    sorted.sort((a, b) => a.$2.compareTo(b.$2));
    for (final (o, z, s) in sorted) {
      linePaint.shader = LinearGradient(
        colors: [
          pal[s.slot].withValues(alpha: 0.0),
          pal[s.slot].withValues(alpha: 0.18 + (z + 2.5) * 0.06),
        ],
      ).createShader(Rect.fromPoints(c, o));
      canvas.drawLine(c, o, linePaint);
    }

    // Le cœur : icosaèdre filaire + faces lumineuses.
    final pts = _ico.map((v) => project(v * (1.0 * beat))).toList();
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (i, j) in _edges) {
      final za = pts[i].$2, zb = pts[j].$2;
      final depth = ((za + zb) / 2 + 1) / 2; // 0 (fond) → 1 (devant)
      edgePaint
        ..strokeWidth = 0.8 + depth * 1.6
        ..shader = LinearGradient(
          colors: [
            Color.lerp(c1, c0, depth)!.withValues(alpha: 0.35 + depth * 0.6),
            Color.lerp(c2, c1, depth)!.withValues(alpha: 0.35 + depth * 0.6),
          ],
        ).createShader(Rect.fromPoints(pts[i].$1, pts[j].$1));
      canvas.drawLine(pts[i].$1, pts[j].$1, edgePaint);
    }
    final dot = Paint();
    for (final (o, z) in pts) {
      dot.color = Colors.white.withValues(alpha: 0.5 + (z + 1) * 0.25);
      canvas.drawCircle(o, 1.8 + (z + 1) * 1.2, dot);
    }
    canvas.drawCircle(
      c,
      scale * 0.42 * beat,
      Paint()
        ..shader = RadialGradient(colors: [Colors.white, c0, c1])
            .createShader(Rect.fromCircle(center: c, radius: scale * 0.42)),
    );

    // Les satellites devant le cœur.
    final satPaint = Paint();
    for (final (o, z, s) in sorted) {
      final k = (z + 2.5) / 5;
      satPaint.color = pal[s.slot].withValues(alpha: 0.25);
      canvas.drawCircle(o, s.size * (0.8 + k) * 2.2, satPaint);
      satPaint.color = pal[s.slot];
      canvas.drawCircle(o, s.size * (0.6 + k * 0.8), satPaint);
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => true;
}
