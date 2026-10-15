import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart';
import '../../../data/models/game_session_model.dart';
import '../providers/game_providers.dart';
import '../engine/puk_huk_game.dart';
import '../engine/puck_component.dart';
import '../engine/board_boundary_component.dart';
import '../services/bot_engine.dart';
import '../../../core/theme/puk_huk_theme.dart';

class MinimapWidget extends ConsumerStatefulWidget {
  final String sessionId;
  final Function(String) onPuckSelect;
  final String themeId;
  final PukHukGame? game;

  const MinimapWidget({
    super.key,
    required this.sessionId,
    required this.onPuckSelect,
    this.themeId = 'cyberpunk',
    this.game,
  });

  @override
  ConsumerState<MinimapWidget> createState() => _MinimapWidgetState();
}

class _MinimapWidgetState extends ConsumerState<MinimapWidget> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  
  double _currentScale = 1.0;
  double _currentViewY = 0.0;
  bool _initialized = false;
  ui.Image? _boardTexture;

  @override
  void initState() {
    super.initState();
    _loadTexture();
    // Re-render every frame to keep the minimap perfectly in sync with Flame
    _ticker = createTicker((_) {
      _updateCamera();
      setState(() {});
    });
    _ticker.start();
  }
  
  Future<void> _loadTexture() async {
    final ByteData data = await rootBundle.load('assets/images/board_surface.jpg');
    final ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    final ui.FrameInfo fi = await codec.getNextFrame();
    if (mounted) {
      setState(() {
        _boardTexture = fi.image;
      });
    }
  }

  void _updateCamera() {
    final baseScale = 180 / 1.25;
    
    if (!_initialized) {
      _currentScale = baseScale;
      _currentViewY = 0.0; // y=0 is the far end of the board
      _initialized = true;
    }

    double targetScale = baseScale;
    double targetViewY = 0.0;

    // Get pucks from provider state OR live physics
    PuckStateModel? activePuck;

    if (widget.game != null) {
      // Live physics pucks
      final livePucks = widget.game!.world.children.whereType<PuckComponent>();
      for (final puck in livePucks) {
        if (puck.status == 'knocked_off') continue;
        if (puck.body.position.y < 1.25) {
          if (activePuck == null || puck.body.position.y < activePuck.y) {
            activePuck = PuckStateModel(
              puckId: puck.puckId,
              ownerId: puck.ownerId,
              x: puck.body.position.x,
              y: puck.body.position.y,
              status: puck.status,
            );
          }
        }
      }
    } else {
      // Fallback to static state
      final sessionState = ref.read(gameSessionProvider(widget.sessionId)).value;
      if (sessionState != null && sessionState.boardState.isNotEmpty) {
        for (final puck in sessionState.boardState) {
          if (puck.status == 'knocked_off') continue;
          if (puck.y < 1.25) {
            if (activePuck == null || puck.y < activePuck.y) {
              activePuck = puck;
            }
          }
        }
      }
    }

    if (activePuck != null) {
      // Zoom in!
      targetScale = baseScale * 1.6;
      final viewWindowHeight = 180 / targetScale;
      // Center the camera on the puck vertically, clamped to the scoring area [0, 1.25]
      targetViewY = activePuck.y - (viewWindowHeight / 2);
      targetViewY = targetViewY.clamp(0.0, 1.25 - viewWindowHeight);
    }

    _currentScale = ui.lerpDouble(_currentScale, targetScale, 0.08)!;
    _currentViewY = ui.lerpDouble(_currentViewY, targetViewY, 0.08)!;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 140,
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.8), width: 2.5),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
          BoxShadow(
            color: const Color(0xFF0D1117).withOpacity(0.9),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5.5),
        child: Stack(
          children: [
            Positioned.fill(
              child: Consumer(
                builder: (context, ref, _) {
                  List<PuckStateModel> pucks = [];
                  if (widget.game != null) {
                    final livePucks = widget.game!.world.children.whereType<PuckComponent>();
                    pucks = livePucks.map((p) => PuckStateModel(
                      puckId: p.puckId,
                      ownerId: p.ownerId,
                      x: p.body.position.x,
                      y: p.body.position.y,
                      status: p.status,
                    )).toList();
                  } else {
                    final sessionState = ref.watch(gameSessionProvider(widget.sessionId)).value;
                    pucks = sessionState?.boardState ?? [];
                  }
                  
                  final player = ref.watch(currentPlayerProvider).value;
                  return CustomPaint(
                    painter: _MinimapPainter(
                      pucks,
                      _currentScale,
                      _currentViewY,
                      _boardTexture,
                      widget.themeId,
                      currentUserId: player?.uid,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  final List<dynamic> pucks;
  final double scale;
  final double viewY;
  final ui.Image? texture;
  final String themeId;
  final String? currentUserId;

  _MinimapPainter(
    this.pucks,
    this.scale,
    this.viewY,
    this.texture,
    this.themeId, {
    this.currentUserId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // We want to show a tight window: from viewY to viewY + viewHeight
    // viewHeight in physics meters is (size.height / scale)
    // To do this, we translate the canvas so that physics Y = viewY is at the top of the container.
    final offsetY = -(viewY * scale);
    
    // Center the board horizontally in the container
    final offsetX = (size.width - (0.56 * scale)) / 2;

    canvas.save();
    canvas.translate(offsetX, offsetY);
    final boardWidthScreen = 0.56 * scale;

    // Draw base depending on theme
    // We always use the FPV image now.
    if (texture != null) {
      // Draw the board_surface.jpg mapped perfectly to the dimensions
      // The image represents the top portion of the board, let's assume it maps 1:1 with the full board or scoring zone.
      // We know boardWidthScreen is 0.56 * scale, length is 3.66 * scale. 
      // Minimap only shows up to 1.25m from the end.
      final fullLengthScreen = PukHukGame.boardLength * scale;
      final paint = Paint();
      // Draw the portion of the texture corresponding to this view Window
      // Actually, since we use `canvas.translate`, we can just draw the whole board and clip it? 
      // We already clip in the Widget tree via ClipRRect, so just draw the whole board!
      canvas.drawImageRect(
        texture!,
        Rect.fromLTWH(0, 0, texture!.width.toDouble(), texture!.height.toDouble()),
        Rect.fromLTWH(0, 0, boardWidthScreen, fullLengthScreen),
        paint,
      );
    } else {
      // Fallback cyberpunk surface
      final bgPaint = Paint()..color = const Color(0xFF0A0F16);
      canvas.drawRect(Rect.fromLTRB(0, 0, boardWidthScreen, 1.25 * scale), bgPaint);

      final circuitPaint = Paint()
        ..color = const Color(0xFF00E5FF).withOpacity(0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      
      canvas.drawLine(Offset(boardWidthScreen * 0.2, 0), Offset(boardWidthScreen * 0.2, 1.25 * scale), circuitPaint);
      canvas.drawLine(Offset(boardWidthScreen * 0.8, 0), Offset(boardWidthScreen * 0.8, 1.25 * scale), circuitPaint);
      canvas.drawLine(Offset(boardWidthScreen * 0.2, 0.4 * scale), Offset(boardWidthScreen * 0.3, 0.5 * scale), circuitPaint);
      canvas.drawLine(Offset(boardWidthScreen * 0.3, 0.5 * scale), Offset(boardWidthScreen * 0.3, 0.8 * scale), circuitPaint);
    }


    // 1. Draw scoring zones using the neon theme colors
    final zoneColors = [
      const Color(0xFF00E5FF), // zone 1 - cyan
      const Color(0xFF00E5FF), // zone 2 - cyan
      const Color(0xFF00E5FF), // zone 3 - cyan
    ];

    for (var i = 0; i < BoardBoundaryComponent.zoneStartFractions.length; i++) {
      final fraction = BoardBoundaryComponent.zoneStartFractions[i];
      final y = PukHukGame.boardLength * (1.0 - fraction);
      final screenY = y * scale;
      
      // Very light tint to highlight zones
      final paint = Paint()
        ..color = zoneColors[i].withOpacity(0.05)
        ..style = PaintingStyle.fill;
      
      double nextY = 0;
      if (i < BoardBoundaryComponent.zoneStartFractions.length - 1) {
        nextY = PukHukGame.boardLength * (1.0 - BoardBoundaryComponent.zoneStartFractions[i+1]) * scale;
      }
      canvas.drawRect(Rect.fromLTRB(0, nextY, boardWidthScreen, screenY), paint);
      
      // Neon glow lines
      final linePaint = Paint()
        ..color = zoneColors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2);
      canvas.drawLine(Offset(0, screenY), Offset(boardWidthScreen, screenY), linePaint);
      
      // Draw zone number text in cyberpunk style
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: zoneColors[i].withOpacity(0.9),
            fontSize: 18 * (scale / (180 / 1.25)), // Scale font size with zoom
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: zoneColors[i], blurRadius: 8)],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (boardWidthScreen - textPainter.width) / 2,
          screenY - textPainter.height - 4, // Just above the line
        ),
      );
    }
    
    // Hanger zone
    final hangerY = PukHukGame.boardLength * (1.0 - BoardBoundaryComponent.hangerStartFraction) * scale;
    canvas.drawLine(
      Offset(0, hangerY),
      Offset(boardWidthScreen, hangerY),
      Paint()..color = const Color(0xFF00E5FF)..strokeWidth = 1.5,
    );

    // Center line (optional, but keep it for reference)
    canvas.drawLine(
      Offset(boardWidthScreen / 2, PukHukGame.boardLength * 0.34 * scale), // Line goes up to 1.25m from the far edge
      Offset(boardWidthScreen / 2, 0), // Go to the end of the board
      Paint()..color = const Color(0xFF00E5FF).withOpacity(0.3)..strokeWidth = 1.0,
    );

    // 2. Draw pucks
    for (final puck in pucks) {
      if (puck.status == 'knocked_off') continue;
      
      final py = puck.y;
      
      // Optimization: cull pucks that are offscreen
      final viewWindowHeight = 180 / scale;
      final radius = PukHukGame.puckRadius;
      if (py < viewY - radius || py > viewY + viewWindowHeight + radius) {
        continue;
      }
      
      final screenX = puck.x * scale;
      final screenY = py * scale;

      final isOpponent = currentUserId != null
          ? puck.ownerId != currentUserId
          : (puck.ownerId == 'bot_1' || puck.ownerId == pukhukBotId);
      final color = isOpponent ? PukHukTheme.secondary : PukHukTheme.primary;
      
      canvas.drawCircle(
        Offset(screenX, screenY),
        radius * scale,
        Paint()..color = color,
      );
      // Inner dot
      canvas.drawCircle(
        Offset(screenX, screenY),
        radius * scale * 0.4,
        Paint()..color = Colors.black45,
      );
    }
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter oldDelegate) => true;
}
