import 'package:flutter_test/flutter_test.dart';
import 'package:puk_huk/services/asset_registry_service.dart';

void main() {
  group('TASK-PKG-APP-PUKHUK: @digitalcanopy/assets Registry & CDN Adapter', () {
    test('hydrates puk-huk and shared seed catalog assets', () async {
      final registry = AssetRegistryService.create();
      final assets = await registry.hydrateCatalog();

      expect(assets.any((a) => a.assetKey == 'puk-puck-standard'), isTrue);
      expect(assets.any((a) => a.assetKey == 'puk-bumper-wood'), isTrue);
      expect(assets.any((a) => a.assetKey == 'puk-lane-surface'), isTrue);
      expect(assets.any((a) => a.assetKey == 'audio-impact-wood-thud'), isTrue);

      expect(
        registry.resolvePuckUrl(),
        '${AssetRegistryService.cdnBaseUrl}/physics/pucks/puck_standard.png',
      );
      expect(
        registry.resolveBumperUrl(),
        '${AssetRegistryService.cdnBaseUrl}/physics/bumpers/bumper_wood.png',
      );
      expect(
        registry.resolvePukHukLaneUrl(),
        '${AssetRegistryService.cdnBaseUrl}/physics/lanes/board_surface.jpg',
      );
    });

    test('supports pack-level and single-key hot-swapping with reactive revision bumps', () async {
      final registry = AssetRegistryService.create();
      await registry.hydrateCatalog();
      final initialRev = registry.swapRevision.value;

      registry.registerPackOverride('ui-pack', 'https://custom-ip.sunshade.icu/ui');
      expect(
        registry.resolveUiSpriteUrl('panel-metal'),
        'https://custom-ip.sunshade.icu/ui/panel-metal.png',
      );

      registry.registerOverride(
        'puk-lane-surface',
        const PukHukAssetOverride(url: 'https://custom-ip.sunshade.icu/maple-lane.png'),
      );
      expect(registry.resolvePukHukLaneUrl(), 'https://custom-ip.sunshade.icu/maple-lane.png');
      expect(registry.swapRevision.value, greaterThan(initialRev));
    });

    test('resolves Flame sprite coordinates for UI telemetry HUD frames', () {
      final registry = AssetRegistryService.create();
      final panelData = registry.resolveFlameUiSpriteData('panel-metal');
      expect(panelData, isNotNull);
      expect(panelData!.srcPosition, [1152.0, 0.0]);
      expect(panelData.srcSize, [128.0, 128.0]);
      expect(panelData.anchor, [0.5, 0.5]);

      registry.registerOverride(
        'panel-metal',
        const PukHukAssetOverride(
          url: 'https://custom-ip.sunshade.icu/panel.png',
          frame: PukHukSpriteBounds(x: 10, y: 20, w: 256, h: 128),
          anchor: PukHukAnchorPoint(ax: 0.0, ay: 0.0),
        ),
      );

      final overridden = registry.resolveFlameUiSpriteData('panel-metal');
      expect(overridden!.srcPosition, [10.0, 20.0]);
      expect(overridden.srcSize, [256.0, 128.0]);
      expect(overridden.anchor, [0.0, 0.0]);
    });
  });
}
