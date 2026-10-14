import 'dart:ui' as ui;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BoardBoundaryComponent — static physics walls for rails plus visual
// rendering of the Kenney wood-grain shuffleboard lane and defined scoring zones.
// ─────────────────────────────────────────────────────────────────────────────
class BoardBoundaryComponent extends BodyComponent {
  final double length;
  final double width;

  BoardBoundaryComponent({required this.length, required this.width})
      : super(renderBody: false);

  // Scoring zone boundaries for standard Table Shuffleboard (from far end)
  // Zone 3 (3pts) closest to far edge, Zone 1 (1pt) closest to centre.
  static const List<double> zoneStartFractions = [0.66, 0.77, 0.88];
  static const double hangerStartFraction = 0.98; // overhang bonus zone (4pts)

  ui.Image? _surfaceTexture;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _surfaceTexture = await game.images.load('board_surface.jpg');
    } catch (_) {
      // Graceful fallback to procedural Kenney wood grain lane
    }
  }

  @override
  Body createBody() {
    final bodyDef = BodyDef(position: Vector2.zero(), type: BodyType.static);
    final body = world.createBody(bodyDef);

    // Gutters are 0.1m wide on each side and far end
    const double gutter = 0.1;

    // Left rail
    _addRail(body, Vector2(-gutter, -gutter), Vector2(-gutter, length));
    // Right rail
    _addRail(body, Vector2(width + gutter, -gutter), Vector2(width + gutter, length));
    // Launch-end wall (bottom edge - flush)
    _addRail(body, Vector2(-gutter, length), Vector2(width + gutter, length));

    return body;
  }

  void _addRail(Body body, Vector2 start, Vector2 end) {
    final shape = EdgeShape()..set(start, end);
    final fixtureDef = FixtureDef(shape, friction: 0.1, restitution: 0.6);
    body.createFixture(fixtureDef);
  }

  /// Determine scoring zone (1-3) for a given y position, or 0 if not scored.
  /// Returns -1 if the puck is a "hanger" (bonus zone).
  static int zoneForPosition(double y, double boardLength) {
    // Launch is at boardLength, so position from launch is (boardLength - y)
    final distance = boardLength - y;
    final fraction = distance / boardLength;
    if (fraction >= hangerStartFraction) return -1; // hanger bonus
    for (var i = zoneStartFractions.length - 1; i >= 0; i--) {
      if (fraction >= zoneStartFractions[i]) return i + 1;
    }
    return 0; // not in a scoring zone
  }

  @override
  void render(Canvas canvas) {
    const double gutter = 0.1;

    // 1. Gutter troughs (dark wood / metal trough around playfield)
    final gutterPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(-gutter, 0),
        Offset(width + gutter, 0),
        const [
          Color(0xFF120E0C),
          Color(0xFF221A16),
          Color(0xFF120E0C),
        ],
      );
    canvas.drawRect(
      Rect.fromLTWH(-gutter, -gutter, width + (2 * gutter), length + gutter),
      gutterPaint,
    );

    // Edge shadow along lane rails
    final railShadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawRect(const Rect.fromLTWH(-0.015, 0, 0.015, 3.66), railShadowPaint);
    canvas.drawRect(Rect.fromLTWH(width, 0, 0.015, length), railShadowPaint);

    // 2. Main Shuffleboard Playing Surface (Kenney Tabletop Wood Grain)
    if (_surfaceTexture != null) {
      canvas.drawImageRect(
        _surfaceTexture!,
        Rect.fromLTWH(0, 0, _surfaceTexture!.width.toDouble(), _surfaceTexture!.height.toDouble()),
        Rect.fromLTWH(0, 0, width, length),
        Paint(),
      );
    } else {
      _renderProceduralWoodLane(canvas);
    }

    // 3. Defined Scoring Zones & Traditional Inlay Lines
    _renderScoringZones(canvas);
  }

  void _renderProceduralWoodLane(Canvas canvas) {
    // 5 lengthwise hardwood planks with warm Kenney maple/oak hues
    const int plankCount = 5;
    final double plankWidth = width / plankCount;
    const plankColors = [
      Color(0xFFE2A654), // Golden maple
      Color(0xFFDA9C48), // Warm amber
      Color(0xFFE7B060), // Honey oak
      Color(0xFFD49742), // Deep oak
      Color(0xFFDC9E4D), // Polished maple
    ];

    for (int i = 0; i < plankCount; i++) {
      final double px = i * plankWidth;
      final plankRect = Rect.fromLTWH(px, 0, plankWidth, length);
      final plankPaint = Paint()..color = plankColors[i % plankColors.length];
      canvas.drawRect(plankRect, plankPaint);

      // Fine grain streaks along Y
      final grainPaint = Paint()
        ..color = const Color(0xFFB37328).withValues(alpha: 0.22)
        ..strokeWidth = 0.0012;
      for (double gx = 0.006; gx < plankWidth; gx += 0.01) {
        canvas.drawLine(Offset(px + gx, 0), Offset(px + gx, length), grainPaint);
      }

      // Inlay seam between planks
      final seamPaint = Paint()
        ..color = const Color(0xFF633D14).withValues(alpha: 0.45)
        ..strokeWidth = 0.0018;
      canvas.drawLine(Offset(px, 0), Offset(px, length), seamPaint);
    }

    // High-gloss lacquer reflection highlight
    final glossPaint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(width, 0),
        [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.14),
          Colors.white.withValues(alpha: 0.0),
        ],
        const [0.25, 0.5, 0.75],
      );
    canvas.drawRect(Rect.fromLTWH(0, 0, width, length), glossPaint);
  }

  void _renderScoringZones(Canvas canvas) {
    // Center foul line (y = length * 0.5)
    final foulY = length * 0.5;
    final foulPaint = Paint()
      ..color = const Color(0xFF4E342E).withValues(alpha: 0.6)
      ..strokeWidth = 0.004;
    canvas.drawLine(Offset(0, foulY), Offset(width, foulY), foulPaint);
    _drawZoneText(canvas, 'FOUL LINE', width / 2, foulY + 0.05, 0.022, const Color(0xFF5D4037));

    // Scoring zones dividers (at 0.66, 0.77, 0.88 distance fractions from launch)
    const zoneFractions = [0.66, 0.77, 0.88];
    const zoneLineColors = [
      Color(0xFF2E7D32), // Zone 1 - Emerald
      Color(0xFF1565C0), // Zone 2 - Cobalt
      Color(0xFFE65100), // Zone 3 - Amber
    ];

    for (int i = 0; i < zoneFractions.length; i++) {
      final y = length * (1.0 - zoneFractions[i]);
      final linePaint = Paint()
        ..color = zoneLineColors[i].withValues(alpha: 0.85)
        ..strokeWidth = 0.005;
      canvas.drawLine(Offset(0, y), Offset(width, y), linePaint);
    }

    // Hanger Line (bonus zone at far overhang edge)
    final hangerY = length * (1.0 - hangerStartFraction);
    final hangerPaint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 0.006;
    canvas.drawLine(Offset(0, hangerY), Offset(width, hangerY), hangerPaint);

    // Zone Numerals painted on the wood surface
    final yZone1 = (length * (1.0 - 0.66) + length * (1.0 - 0.77)) / 2;
    _drawZoneText(canvas, '1', width / 2, yZone1, 0.055, const Color(0xFF2E7D32));

    final yZone2 = (length * (1.0 - 0.77) + length * (1.0 - 0.88)) / 2;
    _drawZoneText(canvas, '2', width / 2, yZone2, 0.055, const Color(0xFF1565C0));

    final yZone3 = (length * (1.0 - 0.88) + hangerY) / 2;
    _drawZoneText(canvas, '3', width / 2, yZone3, 0.055, const Color(0xFFE65100));

    // Hanger bonus indicator
    _drawZoneText(canvas, '★ 4 HANGER ★', width / 2, hangerY * 0.5, 0.016, Colors.amber);
  }

  void _drawZoneText(Canvas canvas, String text, double x, double y, double sizeMeters, Color color) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: 32,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.translate(x, y);
    final scale = sizeMeters / 32.0;
    canvas.scale(scale, scale);
    textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
    canvas.restore();
  }
}
