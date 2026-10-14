import 'package:flutter_test/flutter_test.dart';
import 'package:puk_huk/features/game/engine/board_boundary_component.dart';
import 'package:puk_huk/features/game/providers/game_providers.dart';

void main() {
  group('BoardBoundaryComponent & ScoringZones Tests', () {
    const double boardLength = 3.66;

    test('zoneForPosition accurately detects scoring zones and hangers', () {
      // Launch position (y = 3.66): distance = 0 -> not scored
      expect(BoardBoundaryComponent.zoneForPosition(3.66, boardLength), equals(0));

      // Mid-field (y = 1.83): distance = 1.83 (fraction = 0.50) -> not scored (< 0.66)
      expect(BoardBoundaryComponent.zoneForPosition(1.83, boardLength), equals(0));

      // Zone 1: fraction between 0.66 and 0.77 (distance ~ 2.5m -> y ~ 1.16m)
      expect(BoardBoundaryComponent.zoneForPosition(1.16, boardLength), equals(1));

      // Zone 2: fraction between 0.77 and 0.88 (distance ~ 2.9m -> y ~ 0.76m)
      expect(BoardBoundaryComponent.zoneForPosition(0.76, boardLength), equals(2));

      // Zone 3: fraction between 0.88 and 0.98 (distance ~ 3.3m -> y ~ 0.36m)
      expect(BoardBoundaryComponent.zoneForPosition(0.36, boardLength), equals(3));

      // Hanger Zone: fraction >= 0.98 (distance ~ 3.6m -> y ~ 0.05m)
      expect(BoardBoundaryComponent.zoneForPosition(0.05, boardLength), equals(-1));
    });

    test('ScoringZones calculates correct points per zone', () {
      expect(ScoringZones.pointsForZone(1), equals(1));
      expect(ScoringZones.pointsForZone(2), equals(2));
      expect(ScoringZones.pointsForZone(3), equals(3));
      expect(ScoringZones.pointsForZone(4), equals(4));
      expect(ScoringZones.pointsForZone(-1, isHanger: true), equals(ScoringZones.hangerBonus));
      expect(ScoringZones.pointsForZone(0), equals(0));
    });

    test('TelemetryState holds speed, angle, spin, and aim status', () {
      const state = TelemetryState(
        velocity: 4.8,
        angle: -3.5,
        spin: 1.2,
        isAiming: true,
      );

      expect(state.velocity, equals(4.8));
      expect(state.angle, equals(-3.5));
      expect(state.spin, equals(1.2));
      expect(state.isAiming, isTrue);
    });
  });
}
