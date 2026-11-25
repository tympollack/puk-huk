import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Canonical `@digitalcanopy/assets` R2 CDN base URL and Flame sprite adapter
/// for Puk Huk (`app_scope: 'puk-huk'`).
class PukHukSpriteBounds {
  final double x;
  final double y;
  final double w;
  final double h;

  const PukHukSpriteBounds({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });
}

class PukHukAnchorPoint {
  final double ax;
  final double ay;

  const PukHukAnchorPoint({required this.ax, required this.ay});
}

class PukHukFlameSpriteData {
  final List<double> srcPosition;
  final List<double> srcSize;
  final List<double> anchor;

  const PukHukFlameSpriteData({
    required this.srcPosition,
    required this.srcSize,
    required this.anchor,
  });
}

class PukHukCatalogAsset {
  final String appScope;
  final String category;
  final String assetKey;
  final String cdnUrl;
  final Map<String, dynamic> metadata;

  const PukHukCatalogAsset({
    required this.appScope,
    required this.category,
    required this.assetKey,
    required this.cdnUrl,
    this.metadata = const {},
  });

  factory PukHukCatalogAsset.fromMap(Map<String, dynamic> map) {
    final rawMeta = map['metadata'];
    final Map<String, dynamic> parsedMeta;
    if (rawMeta is Map<String, dynamic>) {
      parsedMeta = rawMeta;
    } else if (rawMeta is String && rawMeta.isNotEmpty) {
      parsedMeta = Map<String, dynamic>.from(jsonDecode(rawMeta) as Map);
    } else {
      parsedMeta = const {};
    }

    return PukHukCatalogAsset(
      appScope: (map['app_scope'] ?? '').toString(),
      category: (map['category'] ?? '').toString(),
      assetKey: (map['asset_key'] ?? '').toString(),
      cdnUrl: (map['cdn_url'] ?? '').toString(),
      metadata: parsedMeta,
    );
  }
}

class PukHukAssetOverride {
  final String url;
  final PukHukSpriteBounds? frame;
  final PukHukAnchorPoint? anchor;
  final Map<String, dynamic> metadata;

  const PukHukAssetOverride({
    required this.url,
    this.frame,
    this.anchor,
    this.metadata = const {},
  });
}

class AssetRegistryService {
  AssetRegistryService._internal();

  static final AssetRegistryService instance = AssetRegistryService._internal();

  /// Factory for isolated unit tests.
  factory AssetRegistryService.create() => AssetRegistryService._internal();

  static const String cdnBaseUrl = 'https://cdn.sunshade.icu/assets/kenney';
  static const String appScope = 'puk-huk';

  /// Canonical UI sprite frame coordinates aligned with `@digitalcanopy/assets` `uiSpritesAtlas`.
  static const Map<String, PukHukSpriteBounds> uiAtlasFrames = {
    'button-default': PukHukSpriteBounds(x: 0, y: 0, w: 128, h: 128),
    'button-hover': PukHukSpriteBounds(x: 128, y: 0, w: 128, h: 128),
    'button-pressed': PukHukSpriteBounds(x: 256, y: 0, w: 128, h: 128),
    'panel-wooden': PukHukSpriteBounds(x: 1024, y: 0, w: 128, h: 128),
    'panel-metal': PukHukSpriteBounds(x: 1152, y: 0, w: 128, h: 128),
    'panel-glass': PukHukSpriteBounds(x: 1280, y: 0, w: 128, h: 128),
    'icon-settings': PukHukSpriteBounds(x: 256, y: 128, w: 128, h: 128),
    'bar-progress-bg': PukHukSpriteBounds(x: 768, y: 128, w: 128, h: 128),
    'bar-progress-fill': PukHukSpriteBounds(x: 896, y: 128, w: 128, h: 128),
  };

  /// Seed dataset matching `@digitalcanopy/assets` `SEED_CATALOG_ASSETS` (`puk-huk` + `all`).
  static const List<PukHukCatalogAsset> seedCatalog = [
    PukHukCatalogAsset(
      appScope: 'puk-huk',
      category: 'physics_puck',
      assetKey: 'puk-puck-standard',
      cdnUrl: '$cdnBaseUrl/physics/pucks/puck_standard.png',
      metadata: {'format': 'png', 'width': 64, 'height': 64, 'license': 'CC0-Kenney', 'radius': 32},
    ),
    PukHukCatalogAsset(
      appScope: 'puk-huk',
      category: 'physics_bumper',
      assetKey: 'puk-bumper-wood',
      cdnUrl: '$cdnBaseUrl/physics/bumpers/bumper_wood.png',
      metadata: {'format': 'png', 'width': 128, 'height': 32, 'license': 'CC0-Kenney', 'restitution': 0.85},
    ),
    PukHukCatalogAsset(
      appScope: 'puk-huk',
      category: 'shuffleboard_lane',
      assetKey: 'puk-lane-surface',
      cdnUrl: '$cdnBaseUrl/physics/lanes/board_surface.jpg',
      metadata: {'format': 'jpg', 'width': 512, 'height': 2048, 'license': 'CC0-Kenney'},
    ),
    PukHukCatalogAsset(
      appScope: 'all',
      category: 'particle_fx',
      assetKey: 'fx-particle-starburst',
      cdnUrl: '$cdnBaseUrl/particles/starburst.png',
      metadata: {'format': 'png', 'width': 64, 'height': 64, 'license': 'CC0-Kenney'},
    ),
    PukHukCatalogAsset(
      appScope: 'all',
      category: 'particle_fx',
      assetKey: 'fx-particle-dust-puff',
      cdnUrl: '$cdnBaseUrl/particles/dust_puff.png',
      metadata: {'format': 'png', 'width': 64, 'height': 64, 'license': 'CC0-Kenney'},
    ),
    PukHukCatalogAsset(
      appScope: 'all',
      category: 'ui_audio',
      assetKey: 'audio-ui-tap',
      cdnUrl: '$cdnBaseUrl/audio/ui/tap_clean.ogg',
      metadata: {'format': 'ogg', 'duration_ms': 85, 'license': 'CC0-Kenney'},
    ),
    PukHukCatalogAsset(
      appScope: 'all',
      category: 'impact_audio',
      assetKey: 'audio-impact-wood-thud',
      cdnUrl: '$cdnBaseUrl/audio/impacts/wood_thud.ogg',
      metadata: {'format': 'ogg', 'duration_ms': 140, 'license': 'CC0-Kenney'},
    ),
  ];

  final Map<String, PukHukAssetOverride> _overrides = {};
  final Map<String, String> _packOverrides = {};
  final ValueNotifier<int> swapRevision = ValueNotifier<int>(0);
  bool _hydrated = false;

  bool get isHydrated => _hydrated;

  void reset() {
    _overrides.clear();
    _packOverrides.clear();
    _hydrated = false;
    swapRevision.value++;
  }

  void registerOverride(String key, PukHukAssetOverride override) {
    _overrides[key.trim()] = override;
    swapRevision.value++;
  }

  void registerPackOverride(String pack, String cdnBase) {
    final cleanPack = pack.replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
    _packOverrides[cleanPack] = cdnBase.replaceAll(RegExp(r'/+$'), '');
    swapRevision.value++;
  }

  bool hasOverride(String key) => _overrides.containsKey(key.trim());

  PukHukAssetOverride? getOverride(String key) => _overrides[key.trim()];

  void loadCatalog(List<PukHukCatalogAsset> assets, {String? scope}) {
    final filtered = scope == null
        ? assets
        : assets.where((a) => a.appScope == scope || a.appScope == 'all');
    for (final asset in filtered) {
      final cleanKey = asset.assetKey.trim();
      if (cleanKey.isEmpty) continue;
      _overrides[cleanKey] = PukHukAssetOverride(
        url: asset.cdnUrl,
        metadata: asset.metadata,
      );
    }
    _hydrated = true;
    swapRevision.value++;
  }

  Future<List<PukHukCatalogAsset>> hydrateCatalog({
    SupabaseClient? supabaseClient,
    bool force = false,
  }) async {
    if (_hydrated && !force) {
      return seedCatalog;
    }

    if (supabaseClient != null) {
      try {
        final rows = await supabaseClient
            .schema('catalog')
            .from('assets')
            .select('app_scope, category, asset_key, cdn_url, metadata')
            .inFilter('app_scope', [appScope, 'all']);

        if (rows is List && rows.isNotEmpty) {
          final parsed = rows
              .whereType<Map<String, dynamic>>()
              .map(PukHukCatalogAsset.fromMap)
              .where((a) => a.assetKey.isNotEmpty && a.cdnUrl.isNotEmpty)
              .toList();
          if (parsed.isNotEmpty) {
            loadCatalog(parsed, scope: appScope);
            return parsed;
          }
        }
      } catch (err) {
        debugPrint('[AssetRegistryService] Remote catalog unavailable, using seed: $err');
      }
    }

    loadCatalog(seedCatalog, scope: appScope);
    return seedCatalog;
  }

  String resolveUrl(String key, {String fallbackUrl = ''}) {
    final cleanKey = key.trim();
    return _overrides[cleanKey]?.url ?? fallbackUrl;
  }

  String resolveAssetUrl(String pack, String assetPath, {String ext = 'png'}) {
    final cleanPack = pack.replaceAll(RegExp(r'^/+|/+$'), '').toLowerCase();
    final cleanPath = assetPath.replaceAll(RegExp(r'^/+|/+$'), '');
    final bareKey = cleanPath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');

    if (_overrides.containsKey(bareKey)) {
      return _overrides[bareKey]!.url;
    }
    if (_overrides.containsKey(cleanPath)) {
      return _overrides[cleanPath]!.url;
    }

    final cleanExt = ext.startsWith('.') ? ext.substring(1) : ext;
    final hasExt = RegExp(r'\.[a-zA-Z0-9]+$').hasMatch(cleanPath);
    final finalPath = hasExt ? cleanPath : '$cleanPath.$cleanExt';

    final packBase = _packOverrides[cleanPack];
    if (packBase != null) {
      return '$packBase/$finalPath';
    }
    return '$cdnBaseUrl/$cleanPack/$finalPath';
  }

  String resolvePukHukLaneUrl() {
    return resolveUrl(
      'puk-lane-surface',
      fallbackUrl: resolveAssetUrl('physics', 'lanes/board_surface', ext: 'jpg'),
    );
  }

  String resolvePuckUrl() {
    return resolveUrl(
      'puk-puck-standard',
      fallbackUrl: resolveAssetUrl('physics', 'pucks/puck_standard'),
    );
  }

  String resolveBumperUrl() {
    return resolveUrl(
      'puk-bumper-wood',
      fallbackUrl: resolveAssetUrl('physics', 'bumpers/bumper_wood'),
    );
  }

  String resolveUiSpriteUrl(String spriteKey) {
    return resolveAssetUrl('ui-pack', spriteKey);
  }

  String resolveAudioUrl(String soundKey, {String ext = 'ogg'}) {
    final cleanKey = soundKey.trim();
    if (_overrides.containsKey(cleanKey)) {
      return _overrides[cleanKey]!.url;
    }
    return resolveAssetUrl('ui-pack', 'sounds/$cleanKey', ext: ext);
  }

  PukHukFlameSpriteData? resolveFlameUiSpriteData(String frameKey) {
    final cleanKey = frameKey.trim();
    final override = _overrides[cleanKey];
    final baseBounds = uiAtlasFrames[cleanKey];
    final frame = override?.frame ?? baseBounds;
    if (frame == null) return null;

    final anchor = override?.anchor ?? const PukHukAnchorPoint(ax: 0.5, ay: 0.5);
    return PukHukFlameSpriteData(
      srcPosition: [frame.x, frame.y],
      srcSize: [frame.w, frame.h],
      anchor: [anchor.ax, anchor.ay],
    );
  }

  Future<ui.Image?> loadCdnImage(
    String url, {
    Future<ByteData> Function(String url)? byteLoader,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      final data = byteLoader != null
          ? await byteLoader(url).timeout(timeout)
          : await NetworkAssetBundle(Uri.parse(url)).load(url).timeout(timeout);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (bytes.isEmpty) {
        return null;
      }
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, (img) {
        if (!completer.isCompleted) {
          completer.complete(img);
        }
      });
      return await completer.future.timeout(timeout);
    } catch (_) {
      return null;
    }
  }
}
