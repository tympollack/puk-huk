import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puk_huk/features/game/engine/particle_emitter_component.dart';

void main() {
  group('PukHukParticleEmitter Tests', () {
    test('initializes with pre-allocated pool and zero active particles', () {
      final emitter = PukHukParticleEmitter(capacity: 50);
      expect(emitter.poolSize, equals(50));
      expect(emitter.activeCount, equals(0));
    });

    test('emitDust activates pooled particles with sliding velocity and auto-disposes', () {
      final emitter = PukHukParticleEmitter(capacity: 50);
      final puckPos = Vector2(0.28, 2.0);
      final puckVel = Vector2(0.0, -1.5);

      emitter.emitDust(puckPos, puckVel, count: 3);
      expect(emitter.activeCount, equals(3));

      // Update emitter past the dust lifetime (e.g., 0.5s)
      emitter.update(0.5);

      // Particles must automatically dispose and return to pool
      expect(emitter.activeCount, equals(0));
    });

    test('emitSparks activates spark particles reflecting from collision normal and auto-disposes', () {
      final emitter = PukHukParticleEmitter(capacity: 50);
      final contactPoint = Vector2(-0.1, 1.5);
      final normal = Vector2(1.0, 0.0);

      emitter.emitSparks(contactPoint, normal, count: 8, impactSpeed: 2.0);
      expect(emitter.activeCount, equals(8));

      // Advance physics time to simulate spark flight
      emitter.update(0.1);
      expect(emitter.activeCount, equals(8));

      // Advance physics time past expiration
      emitter.update(0.4);
      expect(emitter.activeCount, equals(0));
    });

    test('recycles oldest particles when pool capacity is exceeded to prevent memory leaks', () {
      const poolCapacity = 10;
      final emitter = PukHukParticleEmitter(capacity: poolCapacity);

      // Fill entire pool
      emitter.emitSparks(Vector2.zero(), Vector2(1, 0), count: 10);
      expect(emitter.activeCount, equals(10));
      expect(emitter.poolSize, equals(10));

      // Emit more particles than available slots
      emitter.emitDust(Vector2.zero(), Vector2(0, -1), count: 5);

      // Pool size remains strictly clamped to capacity (zero new memory allocated)
      expect(emitter.poolSize, equals(10));
      expect(emitter.activeCount, equals(10));
    });

    test('clear resets all active particles back into pool', () {
      final emitter = PukHukParticleEmitter(capacity: 20);
      emitter.emitSparks(Vector2.zero(), Vector2(0, 1), count: 6);
      expect(emitter.activeCount, equals(6));

      emitter.clear();
      expect(emitter.activeCount, equals(0));
    });
  });
}
