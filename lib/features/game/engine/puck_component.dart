import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PuckComponent — a single shuffleboard puck with full physics simulation.
//
// Visual feedback design:
//   • Speed → motion blur trail (opacity/length scales with velocity)
//   • Rotation → radial spoke marking on puck face (shows actual spin from
//     Box2D angular velocity, not just a cosmetic add-on)
//   • Settling → subtle glow fade as puck decelerates below threshold
// ─────────────────────────────────────────────────────────────────────────────
class PuckComponent extends BodyComponent {
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
      angularDamping: 0.3,
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
    // Drag backward = pull back; forward = launch direction (slingshot feel)
    // Scale distance dragged (e.g. 400px max drag) -> [0.0, 1.0] intensity
    final normalized = dragDelta.clone()..scale(-1);
    final magnitude = (normalized.length / 400.0).clamp(0.0, 1.0);
    normalized.normalize();
    _aimImpulse = normalized..scale(magnitude * maxImpulse);
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
    
    // Gutter check - if puck falls off far edge or goes backwards off the board
    final pos = body.position;
    if (pos.x > 3.66 + radius || pos.x < -radius) {
      body.linearVelocity.setZero();
      body.angularVelocity = 0.0;
      if (status != 'knocked_off') {
        status = 'knocked_off';
        for (final fixture in body.fixtures) {
          fixture.isSensor = true;
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

    // Detect rest state → throw complete
    if (speed < _restThreshold && peakSpeed > 0.05) {
      _isTracking = false;
      _onSettledCallback?.call();
      _onSettledCallback = null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Visual rendering — speed trail + rotation indicator
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
          [color.withOpacity(0.35 * speedRatio), color.withOpacity(0)],
        );
      canvas.drawCircle(Offset.zero, radius * 1.6, trailPaint);
    }

    // ── Puck body ────────────────────────────────────────────────────────
    final bodyPaint = Paint()..color = color;
    canvas.drawCircle(Offset.zero, radius, bodyPaint);

    final rimPaint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.12;
    canvas.drawCircle(Offset.zero, radius * 0.88, rimPaint);

    // ── Rotation indicator (radial spoke, shows real angular velocity) ───
    canvas.save();
    canvas.rotate(body.angle);
    final spokePaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..strokeWidth = radius * 0.18
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset.zero,
      Offset(radius * 0.7, 0),
      spokePaint,
    );
    canvas.restore();

    // ── Speed glow ring (intensifies with velocity) ───────────────────────
    if (speedRatio > 0.1) {
      final glowPaint = Paint()
        ..color = color.withOpacity(0.5 * speedRatio)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.3
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(Offset.zero, radius * 1.1, glowPaint);
    }
    
    if (status == 'knocked_off') {
      canvas.restore();
    }
  }
}
