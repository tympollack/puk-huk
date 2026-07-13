import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BoardBoundaryComponent — static physics walls for the long edges of the
// table (top/bottom rails) plus visual rendering of the lane and scoring
// zone lines. The far end is intentionally open — pucks that cross it
// without stopping in a zone are "off the board" (foul).
// ─────────────────────────────────────────────────────────────────────────────
class BoardBoundaryComponent extends BodyComponent {
  final double length;
  final double width;

  BoardBoundaryComponent({required this.length, required this.width})
      : super(renderBody: false);

  // Scoring zone boundaries as fractions of board length (from far end)
  // Zone 4 (4pts) closest to far edge, Zone 1 (1pt) closest to centre line
  static const List<double> zoneStartFractions = [0.62, 0.74, 0.84, 0.92];
  static const double hangerStartFraction = 0.97; // overhang bonus zone

  @override
  Body createBody() {
    final bodyDef = BodyDef(position: Vector2.zero(), type: BodyType.static);
    final body = world.createBody(bodyDef);

    // Top rail
    _addRail(body, Vector2(0, 0), Vector2(length, 0));
    // Bottom rail
    _addRail(body, Vector2(0, width), Vector2(length, width));
    // Launch-end wall (left edge)
    _addRail(body, Vector2(0, 0), Vector2(0, width));

    return body;
  }

  void _addRail(Body body, Vector2 start, Vector2 end) {
    final shape = EdgeShape()..set(start, end);
    final fixtureDef = FixtureDef(shape, friction: 0.1, restitution: 0.6);
    body.createFixture(fixtureDef);
  }

  @override
  void render(Canvas canvas) {
    final lanePaint = Paint()..color = const Color(0xFF2B3340);
    canvas.drawRect(Rect.fromLTWH(0, 0, length, width), lanePaint);

    // Centre divider line
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..strokeWidth = 0.006;
    canvas.drawLine(Offset(length * 0.5, 0), Offset(length * 0.5, width), linePaint);

    // Scoring zone lines (far half of board)
    final zoneColors = [
      const Color(0xFF4CAF50), // zone 1
      const Color(0xFF8BC34A), // zone 2
      const Color(0xFFFFC107), // zone 3
      const Color(0xFFFF5722), // zone 4
    ];

    for (var i = 0; i < zoneStartFractions.length; i++) {
      final x = length * zoneStartFractions[i];
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, width),
        Paint()
          ..color = zoneColors[i].withOpacity(0.6)
          ..strokeWidth = 0.004,
      );
    }

    // Hanger line (overhang bonus)
    final hangerX = length * hangerStartFraction;
    canvas.drawLine(
      Offset(hangerX, 0),
      Offset(hangerX, width),
      Paint()
        ..color = Colors.amberAccent.withOpacity(0.8)
        ..strokeWidth = 0.006,
    );
  }

  /// Determine scoring zone (1-4) for a given x position, or 0 if not scored.
  /// Returns -1 if the puck is a "hanger" (bonus zone).
  static int zoneForPosition(double x, double boardLength) {
    final fraction = x / boardLength;
    if (fraction >= hangerStartFraction) return -1; // hanger bonus
    for (var i = zoneStartFractions.length - 1; i >= 0; i--) {
      if (fraction >= zoneStartFractions[i]) return i + 1;
    }
    return 0; // not in a scoring zone
  }
}
