import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'puck_component.dart';
import 'board_boundary_component.dart';
import 'aim_indicator_component.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PukHukGame — Forge2D physics world for the shuffleboard table.
//
// Why Forge2D (Box2D) over raw Flame collision detection?
//   • Built-in friction/damping models real shuffleboard puck deceleration
//   • Restitution (bounciness) for puck-vs-puck and puck-vs-rail collisions
//   • Continuous collision detection prevents tunneling at high speed
//   • linearDamping simulates the sand/wax friction strip naturally
//
// Coordinate system: 1 physics unit = 1 metre. Board is 3.66m x 0.56m
// (regulation 12ft table), scaled to fit screen via camera viewport.
// ─────────────────────────────────────────────────────────────────────────────
class PukHukGame extends Forge2DGame with PanDetector {
  // Regulation shuffleboard dimensions (metres)
  static const double boardWidth = 0.56;
  static const double boardLength = 3.66; // standard length (12ft) in meters

  // Physics tuning
  static const double puckRadius = 0.055;       // Increased size for better visibility
  static const double puckFriction = 0.15;
  static const double puckRestitution = 0.35;   // bounce off rails
  static const double linearDamping = 0.45;     // simulates wax-strip friction
  static const double maxLaunchImpulse = 0.06;  // calibrated to prevent flying off

  final void Function(PuckComponent puck)? onPuckSettled;
  final void Function(double speed, double distance)? onThrowComplete;
  final void Function(double velocity, double angle, double spin, bool isAiming)? onTelemetryUpdate;
  final VoidCallback? onPuckLaunched;

  PukHukGame({
    this.onPuckSettled,
    this.onThrowComplete,
    this.onTelemetryUpdate,
    this.onPuckLaunched,
  }) : super(gravity: Vector2.zero()); // top-down view — no gravity

  PuckComponent? _activePuck;
  PuckComponent? get activePuck => _activePuck;
  Vector2? _dragStart;
  Vector2? _aimStart;
  bool _isAiming = false;
  double _initialPuckX = 0;
  AimIndicatorComponent? _aimIndicator;
  bool isPaused = false;

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.visibleGameSize = Vector2(boardWidth + 0.4, boardLength + 0.4);
    camera.viewfinder.position = Vector2(boardWidth / 2, boardLength / 2 - 0.1);
    camera.viewfinder.anchor = Anchor.center;

    world.add(BoardBoundaryComponent(
      length: boardLength,
      width: boardWidth,
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Spawn a new puck at the launch position (back of the board)
  // ─────────────────────────────────────────────────────────────────────────
  PuckComponent? spawnPuck({
    required String ownerId,
    required Color color,
    required String puckId,
  }) {
    if (_activePuck != null) return null;

    final puck = PuckComponent(
      puckId: puckId,
      ownerId: ownerId,
      color: color,
      radius: puckRadius,
      friction: puckFriction,
      restitution: puckRestitution,
      linearDampingValue: linearDamping,
      position: Vector2(boardWidth / 2, boardLength - 0.25), // launch zone at bottom
    );
    world.add(puck);
    _activePuck = puck;
    return puck;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Drag-to-launch gesture handling
  // Drag distance + direction → impulse vector (speed + rotation feedback)
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void onPanStart(DragStartInfo info) {
    if (isPaused) return;
    if (_activePuck != null) {
      _dragStart = info.eventPosition.global;
      _initialPuckX = _activePuck!.body.position.x;
      _isAiming = false;
    }
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (isPaused) return;
    if (_activePuck == null || _dragStart == null) return;
    final currentDrag = info.eventPosition.global;
    final deltaFromStart = currentDrag - _dragStart!;

    if (!_isAiming) {
      // If we haven't pulled back significantly, we are just positioning horizontally.
      if (deltaFromStart.y > 30) {
        // Transition to aiming
        _isAiming = true;
        _aimStart = currentDrag;
        _aimIndicator = AimIndicatorComponent(puck: _activePuck!);
        world.add(_aimIndicator!);
      } else {
        // Positioning: slide puck left/right
        final newX = (_initialPuckX + deltaFromStart.x * 0.003).clamp(puckRadius + 0.02, boardWidth - puckRadius - 0.02);
        _activePuck!.body.setTransform(Vector2(newX, _activePuck!.body.position.y), 0);
        return; // Skip aim update
      }
    }

    if (_isAiming && _aimStart != null) {
      final aimDelta = currentDrag - _aimStart!;
      
      // Give finer control over the angle by dampening the X-axis drag sensitivity.
      // Squash Y-axis so screen distance maps reasonably to world distance.
      final correctedDelta = Vector2(aimDelta.x * 0.02, aimDelta.y * 0.10);
      
      _activePuck!.previewAimVector(correctedDelta, maxLaunchImpulse);

      // Fire live telemetry (speed, angle, projected spin)
      if (onTelemetryUpdate != null) {
        final angleDeg = _activePuck!.aimImpulse.angleToSigned(Vector2(0, -1)) * (180 / math.pi);
        final velocityMagnitude = _activePuck!.aimImpulse.length / 0.0045; // approx mass
        final projectedSpin = -(aimDelta.x * 0.04);
        onTelemetryUpdate!(velocityMagnitude, angleDeg, projectedSpin, true);
      }
    }
  }

  /// Cancels any active aiming/drag state and removes the active puck from the game.
  void cancelActivePuck() {
    if (_aimIndicator != null) {
      _aimIndicator!.removeFromParent();
      _aimIndicator = null;
    }
    if (_activePuck != null) {
      if (_activePuck!.isMounted) {
        _activePuck!.removeFromParent();
      }
      _activePuck = null;
    }
    _dragStart = null;
    _aimStart = null;
    _isAiming = false;
    if (onTelemetryUpdate != null) {
      onTelemetryUpdate!(0.0, 0.0, 0.0, false);
    }
  }

  @override
  void onPanEnd(DragEndInfo info) {
    if (isPaused) return;
    if (_activePuck == null || _dragStart == null) return;

    bool launched = false;

    if (_isAiming && _aimStart != null) {
      final puck = _activePuck!;
      final impulse = puck.consumeAimImpulse();

      if (impulse.length > 0.005) {
        launched = true;
        puck.body.applyLinearImpulse(impulse);
        // Apply angular impulse for authentic spin physics corresponding to lateral release
        final spinImpulse = (impulse.x * 0.004);
        puck.body.applyAngularImpulse(spinImpulse);
        onPuckLaunched?.call();
        puck.startTracking(onSettled: () {
          onPuckSettled?.call(puck);
          onThrowComplete?.call(puck.peakSpeed, puck.totalDistance);
        });
      }

      if (_aimIndicator != null) {
        _aimIndicator!.removeFromParent();
        _aimIndicator = null;
      }
    }

    _dragStart = null;
    _aimStart = null;
    _isAiming = false;

    if (launched) {
      _activePuck = null;
    } else {
      // Subthreshold release or positioning only: retain _activePuck so player can aim again
      if (_activePuck != null) {
        _initialPuckX = _activePuck!.body.position.x;
      }
    }

    if (onTelemetryUpdate != null) {
      onTelemetryUpdate!(0.0, 0.0, 0.0, false);
    }
  }
}
