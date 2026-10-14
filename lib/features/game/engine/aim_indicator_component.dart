import 'dart:ui';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'puk_huk_game.dart';
import 'puck_component.dart';

class AimIndicatorComponent extends PositionComponent with HasGameRef<PukHukGame> {
  final PuckComponent puck;

  AimIndicatorComponent({required this.puck}) : super(priority: 100);

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    final aimImpulse = puck.aimImpulse;
    if (aimImpulse.length == 0) return;

    // Normalize impulse back to a 0.0 - 1.0 scale
    final magnitude = (aimImpulse.length / PukHukGame.maxLaunchImpulse).clamp(0.0, 1.0);
    if (magnitude < 0.01) return;
    
    final direction = aimImpulse.clone()..normalize();

    // The line starts at the puck and extends up to 0.8 meters based on magnitude
    final start = puck.body.position;
    final end = start + (direction * (magnitude * 0.8));

    // Color goes from green (weak) to yellow (medium) to red (max power)
    Color lineColor;
    if (magnitude < 0.5) {
      lineColor = Color.lerp(Colors.green, Colors.yellow, magnitude * 2)!;
    } else {
      lineColor = Color.lerp(Colors.yellow, Colors.red, (magnitude - 0.5) * 2)!;
    }

    final paint = Paint()
      ..color = lineColor.withOpacity(0.8)
      ..strokeWidth = 0.02 // 2cm thick line
      ..strokeCap = StrokeCap.round;

    // 1. Draw dashed line
    final dashLength = 0.05;
    final gapLength = 0.05;
    double currentDistance = puck.radius * 1.5; // Start just outside the puck
    final maxDistance = magnitude * 1.2;

    while (currentDistance < maxDistance) {
      final lineStart = start + (direction * currentDistance);
      final lineEnd = start + (direction * (currentDistance + dashLength).clamp(0.0, maxDistance));
      
      canvas.drawLine(
        Offset(lineStart.x, lineStart.y),
        Offset(lineEnd.x, lineEnd.y),
        paint,
      );
      currentDistance += dashLength + gapLength;
    }

    // 2. Draw Target Ring at the end
    final targetCenter = start + (direction * maxDistance);
    final ringPaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.015;
    
    canvas.drawCircle(Offset(targetCenter.x, targetCenter.y), 0.06, ringPaint);
    
    // Crosshair inside target ring
    canvas.drawLine(
      Offset(targetCenter.x - 0.08, targetCenter.y),
      Offset(targetCenter.x + 0.08, targetCenter.y),
      ringPaint,
    );
    canvas.drawLine(
      Offset(targetCenter.x, targetCenter.y - 0.08),
      Offset(targetCenter.x, targetCenter.y + 0.08),
      ringPaint,
    );
  }
}
