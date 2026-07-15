import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/material.dart';

import 'puck_component.dart';
import 'board_boundary_component.dart';

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
  static const double boardLength = 3.66;
  static const double boardWidth = 0.56;

  // Physics tuning
  static const double puckRadius = 0.038;       // ~7.6cm diameter puck
  static const double puckFriction = 0.15;
  static const double puckRestitution = 0.35;   // bounce off rails
  static const double linearDamping = 0.45;     // simulates wax-strip friction
  static const double maxLaunchImpulse = 6.0;  // N·s — caps max throw power

  final void Function(PuckComponent puck)? onPuckSettled;
  final void Function(double speed, double distance)? onThrowComplete;

  PukHukGame({this.onPuckSettled, this.onThrowComplete})
      : super(gravity: Vector2.zero()); // top-down view — no gravity

  PuckComponent? _activePuck;
  PuckComponent? get activePuck => _activePuck;
  Vector2? _dragStart;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    camera.viewfinder.visibleGameSize = Vector2(boardLength, boardWidth + 0.4);
    camera.viewfinder.position = Vector2(boardLength / 2, boardWidth / 2);
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
      position: Vector2(0.25, boardWidth / 2), // launch zone
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
    _dragStart = info.eventPosition.global;
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (_activePuck == null || _dragStart == null) return;
    final delta = info.eventPosition.global - _dragStart!;
    _activePuck!.previewAimVector(delta, maxLaunchImpulse);
  }

  @override
  void onPanEnd(DragEndInfo info) {
    if (_activePuck == null || _dragStart == null) return;

    final puck = _activePuck!;
    final impulse = puck.consumeAimImpulse();

    if (impulse.length > 0.1) {
      puck.body.applyLinearImpulse(impulse);
      puck.startTracking(onSettled: () {
        onPuckSettled?.call(puck);
        onThrowComplete?.call(puck.peakSpeed, puck.totalDistance);
      });
    }

    _dragStart = null;
    _activePuck = null;
  }
}
