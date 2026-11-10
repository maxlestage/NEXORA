import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexora/ui/widgets/quota_badge.dart';

void main() {
  test('la jauge de crédit n\'a aucune ligne de séparation', () async {
    const size = 200.0;
    final r = const Rect.fromLTWH(0, 0, size, size).deflate(10);
    final rec = ui.PictureRecorder();
    Canvas(rec).drawArc(
      r,
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..shader = gaugeShader(r, const Color(0xFF22D3EE)),
    );
    final img = await rec.endRecording().toImage(size.toInt(), size.toInt());
    final px = (await img.toByteData())!;
    int alpha(double a) {
      final x = (r.center.dx + math.cos(a) * r.width / 2).round();
      final y = (r.center.dy + math.sin(a) * r.height / 2).round();
      return px.getUint8((y * size.toInt() + x) * 4 + 3);
    }

    // Tout le long de l'arc (135° → 405°), la couleur change en douceur.
    final samples = [
      for (var k = 2; k <= 268; k++) alpha((135 + k) * math.pi / 180),
    ];
    var worst = 0;
    for (var k = 1; k < samples.length; k++) {
      worst = math.max(worst, (samples[k] - samples[k - 1]).abs());
    }
    expect(worst, lessThan(8), reason: 'saut de $worst entre deux degrés');
    // Et il va bien du pâle au vif.
    expect(samples.last - samples.first, greaterThan(60));
  });
}
