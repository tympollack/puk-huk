import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'puk_huk_game.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PuckComponent — a single shuffleboard puck with full physics simulation.
//
// Visual feedback design:
//   • Speed → motion blur trail + perimeter speed glow
//   • Rotational notch markers → cardinal perimeter notches + primary arrow
//     locked directly to Box2D body.angle
//   • Spin physics visualization → dynamic angular vortex arcs scaling with
//     Box2D body.angularVelocity
//   • Settling → subtle glow fade as puck decelerates below rest threshold
// ─────────────────────────────────────────────────────────────────────────────
class PuckComponent extends BodyComponent {
  PukHukGame? get _game => game is PukHukGame ? (game as PukHukGame) : null;
  final String puckId;
  final String ownerId;
  final Color color;
  final double radius;
  final double friction;
  final double restitution;
  final double linearDampingValue;
  final Vector2 _spawnPosition;
  String status;

  PuckComponent({
    required this.puckId,
    required this.ownerId,
    required this.color,
    required this.radius,
    required this.friction,
    required this.restitution,
    required this.linearDampingValue,
    required Vector2 position,
    this.status = 'active',
  })  : _spawnPosition = position,
        super(renderBody: false);

  // ── Tracking state ──────────────────────────────────────────────────────
  double peakSpeed = 0.0;       // m/s — highest velocity reached this throw
  double totalDistance = 0.0;   // m — cumulative path length this throw
  Vector2 _lastPosition = Vector2.zero();
  bool _isTracking = false;
  VoidCallback? _onSettledCallback;

  // ── Aim preview (drag-to-launch) ────────────────────────────────────────
  Vector2 _aimImpulse = Vector2.zero();

  // Velocity below this = considered "at rest"
  static const double _restThreshold = 0.03;

  @override
  Body createBody() {
    final shape = CircleShape()..radius = radius;

    final fixtureDef = FixtureDef(
      shape,
      friction: friction,
      restitution: restitution,
      density: 2.7, // aluminum-ish puck density
      isSensor: status == 'knocked_off',
    );

    final bodyDef = BodyDef(
      position: _spawnPosition,
      type: BodyType.dynamic,
      linearDamping: linearDampingValue,
      angularDamping: 0.4,
      userData: this,
    );

    final body = world.createBody(bodyDef);
    body.createFixture(fixtureDef);
    return body;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Aim preview — called continuously during drag gesture
  // ─────────────────────────────────────────────────────────────────────────
  void previewAimVector(Vector2 dragDelta, double maxImpulse) {
    // Set puck visual rotation to match the angle of the drag cursor
    final angle = math.atan2(dragDelta.y, dragDelta.x);
    body.setTransform(body.position, angle);

    // dragDelta is in physics units (meters) because of camera zoom.
    // 0.8 physics units is a full pull.
    final normalized = dragDelta.clone()..scale(-1);
    double progress = (normalized.length / 0.8).clamp(0.0, 1.0);
    normalized.normalize();
    _aimImpulse = normalized..scale(progress * maxImpulse);
  }

  Vector2 get aimImpulse => _aimImpulse;

  void setAimImpulse(Vector2 impulse) {
    _aimImpulse = impulse;
  }

  Vector2 consumeAimImpulse() {
    final impulse = _aimImpulse.clone();
    _aimImpulse = Vector2.zero();
    return impulse;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Begin tracking peak speed + distance for this throw
  // ─────────────────────────────────────────────────────────────────────────
  void startTracking({required VoidCallback onSettled}) {
    _isTracking = true;
    peakSpeed = 0.0;
    totalDistance = 0.0;
    _lastPosition = body.position.clone();
    _onSettledCallback = onSettled;
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // Gutter check - if puck falls off side gutters
    final pos = body.position;
    if (pos.y < -radius || pos.x < -radius || pos.x > 0.56 + radius) {
      body.linearVelocity.setZero();
      body.angularVelocity = 0.0;
      if (status != 'knocked_off') {
        status = 'knocked_off';
        for (final fixture in body.fixtures) {
          fixture.setSensor(true);
        }
      }
    }

    if (!_isTracking) return;

    final velocity = body.linearVelocity;
    final speed = velocity.length;

    // Track peak speed
    if (speed > peakSpeed) peakSpeed = speed;

    // Accumulate distance travelled
    final currentPos = body.position;
    totalDistance += currentPos.distanceTo(_lastPosition);
    _lastPosition = currentPos.clone();

    // Stream live telemetry while in flight
    if (_game?.onTelemetryUpdate != null) {
      final angleDeg = speed > 0.02
          ? (velocity.angleToSigned(Vector2(0, -1)) * (180 / math.pi))
          : 0.0;
      final spinRps = body.angularVelocity / (2 * math.pi);
      _game!.onTelemetryUpdate!(speed, angleDeg, spinRps, false);
    }

    // Custom non-linear friction at low speeds to prevent infinite sliding
    if (speed > 0 && speed < 0.6) {
      // Increase damping significantly at low speeds (static friction effect)
      body.linearDamping = linearDampingValue + (0.6 - speed) * 8.0;
    } else {
      body.linearDamping = linearDampingValue;
    }

    // Detect rest state → throw complete
    if (speed < _restThreshold && peakSpeed > 0.05) {
      _isTracking = false;
      _onSettledCallback?.call();
      _onSettledCallback = null;
      _game?.onTelemetryUpdate?.call(0.0, 0.0, 0.0, false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Visual rendering — 2.5D extrusion + rotational notch markers + spin visual
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void render(Canvas canvas) {
    if (status == 'knocked_off') {
      canvas.saveLayer(null, Paint()..color = const Color(0x66FFFFFF)); // dim to 40%
    }
  
    final speed = body.linearVelocity.length;
    final speedRatio = (speed / 3.0).clamp(0.0, 1.0); // normalize vs ~3 m/s max

    // ── Motion blur trail (speed feedback) ──────────────────────────────
    if (speedRatio > 0.05) {
      final trailDir = body.linearVelocity.normalized();
      final trailLength = radius * (1 + speedRatio * 4);
      final trailPaint = Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(-trailDir.x * trailLength, -trailDir.y * trailLength),
          [color.withValues(alpha: 0.35 * speedRatio), color.withValues(alpha: 0)],
        );
      canvas.drawCircle(Offset.zero, radius * 1.6, trailPaint);
    }

    // ── 3D Extrusion Logic ──────────────────────────────────────────────
    final double thickness = radius * 2.0;
    final Offset topOffset = Offset(0, -thickness);

    // 1. Base Shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(0, radius * 0.25), radius * 0.9, shadowPaint);

    // 2. Side Walls (Stacked Cylindrical Slices)
    final wallPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(-radius, 0),
        Offset(radius, 0),
        const [Color(0xFF10141A), Color(0xFF5A6370), Color(0xFF10141A)],
        const [0.0, 0.5, 1.0],
      );

    const int layers = 16;
    for (int i = 0; i <= layers; i++) {
      final double progress = i / layers;
      final Offset currentOffset = Offset(0, topOffset.dy * progress);
      canvas.drawCircle(currentOffset, radius, wallPaint);
    }

    // ── TOP SURFACE ─────────────────────────────────────────────────────
    canvas.save();
    canvas.translate(topOffset.dx, topOffset.dy);

    // 3. Outer Metallic Casing
    final casingPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(-radius * 0.2, -radius * 0.2),
        radius,
        const [Color(0xFF5A6370), Color(0xFF0A0D12)],
      );
    canvas.drawCircle(Offset.zero, radius, casingPaint);

    // 4. Colored Metallic Team Ring
    final coloredRingPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(-radius * 0.3, -radius * 0.3),
        radius * 0.9,
        [color, color.withValues(alpha: 0.5)],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.3;
    canvas.drawCircle(Offset.zero, radius * 0.75, coloredRingPaint);

    // Glowing Neon Core
    final neonPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.05
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 1);
    canvas.drawCircle(Offset.zero, radius * 0.75, neonPaint);

    // 5. Center Cap Dome
    final capPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(-radius * 0.2, -radius * 0.2),
        radius * 0.6,
        const [Color(0xFF2C313A), Color(0xFF000000)],
      );
    canvas.drawCircle(Offset.zero, radius * 0.6, capPaint);
    
    // Glossy Specular Highlight on Center Cap
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-radius * 0.15, -radius * 0.25), width: radius * 0.5, height: radius * 0.2),
      highlightPaint,
    );

    // 6. Rotational Notch Markers & Spin Visualization (Locked to body.angle)
    canvas.save();
    canvas.rotate(body.angle);

    // Cardinal perimeter notches (4 precision notches at 90° intervals)
    final notchPaint = Paint()
      ..color = const Color(0xFF0A0D12)
      ..strokeWidth = radius * 0.16
      ..strokeCap = StrokeCap.square;
    
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(
        Offset(radius * 0.65, 0),
        Offset(radius * 0.92, 0),
        notchPaint,
      );
      canvas.rotate(math.pi / 2);
    }

    // Primary Orientation Notch / Chevron at 0° (bright indicator)
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    final arrowPath = Path()
      ..moveTo(radius * 0.88, 0)
      ..lineTo(radius * 0.68, -radius * 0.09)
      ..lineTo(radius * 0.68, radius * 0.09)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);

    // Center crosshair / spin hub
    final hubPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = radius * 0.04
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset.zero, radius * 0.22, hubPaint);
    canvas.drawLine(Offset(-radius * 0.15, 0), Offset(radius * 0.15, 0), hubPaint);
    canvas.drawLine(Offset(0, -radius * 0.15), Offset(0, radius * 0.15), hubPaint);

    // ── Dynamic Spin Vortex Visualizer (Scaling with body.angularVelocity) ──
    final spinVelocity = body.angularVelocity;
    if (spinVelocity.abs() > 0.08) {
      final spinIntensity = (spinVelocity.abs() / 8.0).clamp(0.2, 0.85);
      final spinDirection = spinVelocity > 0 ? 1.0 : -1.0;
      final sweepAngle = (math.pi / 3.0) * spinDirection * spinIntensity;

      final spinArcPaint = Paint()
        ..color = (spinVelocity > 0 ? Colors.cyanAccent : Colors.amberAccent)
            .withValues(alpha: spinIntensity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.08
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);

      // Draw dual spin streak arcs trailing from opposite notches
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius * 0.8),
        0,
        sweepAngle,
        false,
        spinArcPaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: radius * 0.8),
        math.pi,
        sweepAngle,
        false,
        spinArcPaint,
      );
    }

    canvas.restore(); // Restore from rotation

    // 7. Glossy Resin Top Sheen
    final specularPaint = Paint()
      ..shader = ui.Gradient.radial(
        Offset(-radius * 0.1, -radius * 0.2),
        radius * 0.7,
        const [Color(0xCCFFFFFF), Color(0x00FFFFFF)],
        const [0.0, 1.0],
      );
    canvas.save();
    canvas.translate(-radius * 0.15, -radius * 0.3);
    canvas.scale(1.0, 0.6);
    canvas.drawCircle(Offset.zero, radius * 0.7, specularPaint);
    canvas.restore();
    
    canvas.restore(); // Restore from Top Surface translation

    // ── Speed Glow Ring ──────────────────────────────────────────────────
    if (speedRatio > 0.1) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.6 * speedRatio)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.4
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(Offset.zero, radius * 1.15, glowPaint);
    }
    
    if (status == 'knocked_off') {
      canvas.restore();
    }
  }
}
