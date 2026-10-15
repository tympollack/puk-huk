import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PooledParticle & PukHukParticleEmitter
//
// High-performance particle engine with zero-allocation pooling.
// Supports:
//   1. Trailing dust on puck slides (table shuffleboard wax & sand particles)
//   2. Collision sparks on bumper wall collisions (reflecting outward from normal)
//
// Invariant:
//   • Fixed pre-allocated particle pool — no allocations during game loops
//   • Automatic particle disposal back into pool upon lifetime expiration
// ─────────────────────────────────────────────────────────────────────────────

enum PukParticleType { dust, spark }

class PooledParticle {
  Vector2 position = Vector2.zero();
  Vector2 velocity = Vector2.zero();
  double life = 0.0;
  double maxLife = 0.4;
  double startSize = 0.01;
  double endSize = 0.02;
  Color startColor = Colors.white;
  Color endColor = Colors.transparent;
  bool active = false;
  PukParticleType type = PukParticleType.dust;

  void reset() {
    active = false;
    life = 0.0;
    position.setZero();
    velocity.setZero();
  }
}

class PukHukParticleEmitter extends Component {
  final int capacity;
  late final List<PooledParticle> _pool;
  final math.Random _random = math.Random();

  // Cached paint objects to avoid garbage collection allocations on every frame
  final Paint _dustPaint = Paint()..style = PaintingStyle.fill;
  final Paint _sparkPaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;

  PukHukParticleEmitter({this.capacity = 120}) {
    _pool = List<PooledParticle>.generate(capacity, (_) => PooledParticle());
  }

  int get activeCount => _pool.where((p) => p.active).length;
  int get poolSize => _pool.length;

  void clear() {
    for (final p in _pool) {
      p.reset();
    }
  }

  PooledParticle? _acquireParticle() {
    // 1. Try to find first inactive particle in pool
    for (var i = 0; i < capacity; i++) {
      if (!_pool[i].active) {
        return _pool[i];
      }
    }

    // 2. If pool exhausted, recycle the particle nearest to expiration
    PooledParticle? oldest;
    double maxProgress = -1;
    for (var i = 0; i < capacity; i++) {
      final progress = _pool[i].life / _pool[i].maxLife;
      if (progress > maxProgress) {
        maxProgress = progress;
        oldest = _pool[i];
      }
    }
    oldest?.reset();
    return oldest;
  }

  /// Emit trailing dust on puck slides (shuffleboard sand/wax friction)
  void emitDust(Vector2 puckPosition, Vector2 puckVelocity, {int count = 2}) {
    final speed = puckVelocity.length;
    if (speed < 0.1) return;

    final normVel = puckVelocity.normalized();

    for (var i = 0; i < count; i++) {
      final p = _acquireParticle();
      if (p == null) break;

      // Spawn slightly behind the puck center
      final offsetAngle = (_random.nextDouble() - 0.5) * 0.8;
      final spawnOffset = Vector2(-normVel.x, -normVel.y)
        ..rotate(offsetAngle)
        ..scale(0.04 + _random.nextDouble() * 0.02);

      p.position.setFrom(puckPosition + spawnOffset);

      // Mild drift backwards + lateral dispersion
      final lateral = Vector2(-normVel.y, normVel.x)..scale((_random.nextDouble() - 0.5) * 0.15);
      p.velocity.setFrom(Vector2(-normVel.x, -normVel.y)..scale(0.05 + _random.nextDouble() * 0.08)..add(lateral));

      p.life = 0.0;
      p.maxLife = 0.28 + _random.nextDouble() * 0.16;
      p.startSize = 0.007 + _random.nextDouble() * 0.005;
      p.endSize = 0.016 + _random.nextDouble() * 0.008;

      // Kenney shuffleboard wax/sand hues (wheat, tan, sand)
      final hues = [
        const Color(0xFFEAD8B1),
        const Color(0xFFD2B48C),
        const Color(0xFFC7A87E),
      ];
      final color = hues[_random.nextInt(hues.length)];
      p.startColor = color.withValues(alpha: 0.6);
      p.endColor = color.withValues(alpha: 0.0);
      p.type = PukParticleType.dust;
      p.active = true;
    }
  }

  /// Emit collision sparks on bumper rail / boundary impacts
  void emitSparks(Vector2 contactPoint, Vector2 normal, {int count = 10, double impactSpeed = 1.0}) {
    final effectiveCount = count.clamp(4, 20);

    for (var i = 0; i < effectiveCount; i++) {
      final p = _acquireParticle();
      if (p == null) break;

      p.position.setFrom(contactPoint);

      // Reflect sparks roughly along reflection normal with wide angular dispersion
      final spreadAngle = (_random.nextDouble() - 0.5) * 1.6;
      final speed = (0.4 + _random.nextDouble() * 0.8) * (0.8 + impactSpeed * 0.3);

      final dir = Vector2(normal.x, normal.y)
        ..rotate(spreadAngle)
        ..normalize()
        ..scale(speed);

      p.velocity.setFrom(dir);
      p.life = 0.0;
      p.maxLife = 0.20 + _random.nextDouble() * 0.18;
      p.startSize = 0.006 + _random.nextDouble() * 0.004;
      p.endSize = 0.001;

      // Kenney particle spark hues (gold, bright orange, hot white)
      final sparkHues = [
        const Color(0xFFFFFFFF),
        const Color(0xFFFFEE58),
        const Color(0xFFFF9800),
        const Color(0xFFFF5722),
      ];
      final col = sparkHues[_random.nextInt(sparkHues.length)];
      p.startColor = col;
      p.endColor = col.withValues(alpha: 0.0);
      p.type = PukParticleType.spark;
      p.active = true;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    for (var i = 0; i < capacity; i++) {
      final p = _pool[i];
      if (!p.active) continue;

      p.life += dt;
      if (p.life >= p.maxLife) {
        // Automatic disposal upon completion
        p.active = false;
        continue;
      }

      // Physics integration with frame-rate independent friction decay (zero allocation)
      p.position.addScaled(p.velocity, dt);
      if (p.type == PukParticleType.dust) {
        p.velocity.scale(math.pow(0.88, dt * 60).toDouble());
      } else {
        p.velocity.scale(math.pow(0.92, dt * 60).toDouble());
      }
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);

    for (var i = 0; i < capacity; i++) {
      final p = _pool[i];
      if (!p.active) continue;

      final progress = (p.life / p.maxLife).clamp(0.0, 1.0);
      final currentColor = Color.lerp(p.startColor, p.endColor, progress) ?? p.startColor;
      final currentSize = (p.startSize + (p.endSize - p.startSize) * progress).clamp(0.001, 0.04);

      if (p.type == PukParticleType.dust) {
        _dustPaint.color = currentColor;
        canvas.drawCircle(Offset(p.position.x, p.position.y), currentSize, _dustPaint);
      } else {
        _sparkPaint
          ..color = currentColor
          ..strokeWidth = currentSize;

        // Draw spark streak pointing back along velocity vector (zero vector allocation)
        final tailX = p.position.x - p.velocity.x * 0.025;
        final tailY = p.position.y - p.velocity.y * 0.025;
        canvas.drawLine(
          Offset(p.position.x, p.position.y),
          Offset(tailX, tailY),
          _sparkPaint,
        );
      }
    }
  }
}
