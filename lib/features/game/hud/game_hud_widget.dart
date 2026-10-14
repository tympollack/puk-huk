import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/puk_huk_theme.dart';
import '../../../data/models/game_session_model.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../services/realtime_sync_service.dart';
import '../providers/game_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GameHudWidget
// Floating overlay rendered above the Flame game canvas.
// Receives live session state from RTDB via gameSessionProvider.
// ─────────────────────────────────────────────────────────────────────────────
class GameHudWidget extends ConsumerWidget {
  final String sessionId;
  final String localPlayerId;

  const GameHudWidget({
    super.key,
    required this.sessionId,
    required this.localPlayerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(gameSessionProvider(sessionId));

    return sessionAsync.when(
      data: (session) => _HudOverlay(
        sessionId: sessionId,
        session: session,
        localPlayerId: localPlayerId,
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Main overlay — positions all HUD panels
// ─────────────────────────────────────────────────────────────────────────────
class _HudOverlay extends StatelessWidget {
  final String sessionId;
  final GameSessionState session;
  final String localPlayerId;

  const _HudOverlay({
    required this.sessionId,
    required this.session,
    required this.localPlayerId,
  });

  String get _oppId => session.scores.keys.firstWhere(
        (id) => id != localPlayerId,
        orElse: () => '',
      );

  @override
  Widget build(BuildContext context) {
    final myScore = session.scores[localPlayerId] ?? 0;
    final oppScore = session.scores[_oppId] ?? 0;
    final isMyTurn = session.currentTurnPlayerId == localPlayerId;

    return Stack(
      children: [
        // ── Bottom Dashboard (Kenney Space UI Telemetry & Turn) ─────────
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: _TelemetryDashboard(
            sessionId: sessionId,
            localPlayerId: localPlayerId,
            isMyTurn: isMyTurn,
            scoreBanner: _ScoreBanner(
              localPlayerId: localPlayerId,
              oppId: _oppId,
              myScore: myScore,
              oppScore: oppScore,
              round: session.turnNumber,
              totalRounds: 10,
            ),
          ),
        ),

        // ── Round transition splash ──────────────────────────────────
        if (session.status == 'waiting')
          const _WaitingOverlay(),

        // ── Pause Button ─────────────────────────────────────────────
        Positioned(
          top: MediaQuery.of(context).size.height * 0.5,
          right: 16,
          child: _PauseButton(
            sessionId: sessionId,
            localPlayerId: localPlayerId,
            pausesUsed: session.pausesUsed[localPlayerId] ?? 0,
            isPaused: session.status == 'paused',
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Score Banner — top-center pill showing scores + round counter
// ─────────────────────────────────────────────────────────────────────────────
class _ScoreBanner extends ConsumerWidget {
  final String localPlayerId;
  final String oppId;
  final int myScore, oppScore, round, totalRounds;

  const _ScoreBanner({
    required this.localPlayerId,
    required this.oppId,
    required this.myScore,
    required this.oppScore,
    required this.round,
    required this.totalRounds,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localPlayerName = ref.watch(playerByIdProvider(localPlayerId)).value?.displayName.toUpperCase() ?? 'PLAYER 1';
    final oppName = ref.watch(playerByIdProvider(oppId)).value?.displayName.toUpperCase() ?? 'OPPONENT';

    return Center(
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          gradient: PukHukTheme.metallicGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black54, width: 2),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 10, offset: const Offset(0, 5)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left (My Score)
            Container(
              width: 90,
              decoration: const BoxDecoration(
                color: Color(0xFF111418),
                borderRadius: BorderRadius.horizontal(left: Radius.circular(14)),
                border: Border(right: BorderSide(color: Colors.black, width: 2)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AnimatedScore(score: myScore, color: PukHukTheme.primary),
                  Text(
                    localPlayerName.length > 10 ? localPlayerName.substring(0, 10) : localPlayerName, 
                    style: GoogleFonts.orbitron(fontSize: 8, color: PukHukTheme.primary, letterSpacing: 1),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Center (Turn Info)
            Container(
              width: 70,
              color: const Color(0xFF22272E),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('TURN', style: GoogleFonts.orbitron(fontSize: 8, color: PukHukTheme.textSecondary, letterSpacing: 2)),
                  Text('$round', style: GoogleFonts.orbitron(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
            ),

            // Right (Opp Score)
            Container(
              width: 90,
              decoration: const BoxDecoration(
                color: Color(0xFF111418),
                borderRadius: BorderRadius.horizontal(right: Radius.circular(14)),
                border: Border(left: BorderSide(color: Colors.black, width: 2)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _AnimatedScore(score: oppScore, color: PukHukTheme.secondary),
                  Text(
                    oppName.length > 10 ? oppName.substring(0, 10) : oppName, 
                    style: GoogleFonts.orbitron(fontSize: 8, color: PukHukTheme.secondary, letterSpacing: 1),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedScore extends StatelessWidget {
  final int score;
  final Color color;

  const _AnimatedScore({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      score.toString().padLeft(2, '0'),
      style: GoogleFonts.orbitron(
        fontSize: 38,
        fontWeight: FontWeight.w700,
        color: color,
        shadows: [Shadow(color: color.withValues(alpha: 0.45), blurRadius: 14)],
      ),
    )
        .animate(key: ValueKey(score))
        .scale(
          begin: const Offset(1.35, 1.35),
          end: const Offset(1, 1),
          duration: 350.ms,
          curve: Curves.elasticOut,
        )
        .fade(begin: 0.5, end: 1.0, duration: 200.ms);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Telemetry Dashboard — Kenney Space UI Gauges + Turn Indicator
// ─────────────────────────────────────────────────────────────────────────────
class _TelemetryDashboard extends ConsumerWidget {
  final String sessionId;
  final String localPlayerId;
  final bool isMyTurn;
  final Widget scoreBanner;

  const _TelemetryDashboard({
    required this.sessionId,
    required this.localPlayerId,
    required this.isMyTurn,
    required this.scoreBanner,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(telemetryProvider);
    final sessionState = ref.watch(gameSessionProvider(sessionId)).value;

    // Remaining shots: 4 total pucks per round per player
    final myPucksThrown = sessionState?.boardState.where((p) => p.ownerId == localPlayerId).length ?? 0;
    final myShotsRemaining = (4 - myPucksThrown).clamp(0, 4);

    return Container(
      height: MediaQuery.of(context).size.height * 0.32,
      decoration: const BoxDecoration(
        color: Colors.transparent,
      ),
      child: Column(
        children: [
          // ── Kenney Space UI Telemetry Strip ─────────────────────────
          _SpaceUiTelemetryStrip(
            telemetry: telemetry,
            myShotsRemaining: myShotsRemaining,
          ),

          const Spacer(),

          scoreBanner,

          const Spacer(),

          // Centered "YOUR TURN" Touchpad
          if (isMyTurn)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: PukHukTheme.primary, width: 2),
                    boxShadow: [
                      BoxShadow(color: PukHukTheme.primary.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 2),
                    ],
                  ),
                  child: Text(
                    '▲  YOUR TURN  ▲',
                    style: GoogleFonts.orbitron(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: PukHukTheme.primary,
                      letterSpacing: 2,
                    ),
                  ),
                ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.6, end: 1.0, duration: 800.ms),
                const SizedBox(width: 16),
                _TurnCountdownTimer(sessionId: sessionId),
              ],
            )
          else 
            _TurnCountdownTimer(sessionId: sessionId),

          const Spacer(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Kenney Space UI Telemetry Strip — Gauges for Speed, Trajectory, & Shots
// ─────────────────────────────────────────────────────────────────────────────
class _SpaceUiTelemetryStrip extends StatelessWidget {
  final TelemetryState telemetry;
  final int myShotsRemaining;

  const _SpaceUiTelemetryStrip({
    required this.telemetry,
    required this.myShotsRemaining,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xE60A0E17), // Deep dark glass
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.35), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // 1. Launch Speed Gauge
          Expanded(
            child: _SpaceUiSpeedGauge(velocity: telemetry.velocity),
          ),
          const SizedBox(width: 8),

          // 2. Trajectory Angle Gauge
          Expanded(
            child: _SpaceUiAngleGauge(angle: telemetry.angle),
          ),
          const SizedBox(width: 8),

          // 3. Remaining Shots Gauge
          Expanded(
            child: _SpaceUiShotsGauge(remainingShots: myShotsRemaining),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Kenney Space UI Launch Speed Gauge
// ─────────────────────────────────────────────────────────────────────────────
class _SpaceUiSpeedGauge extends StatelessWidget {
  final double velocity;

  const _SpaceUiSpeedGauge({required this.velocity});

  @override
  Widget build(BuildContext context) {
    // 0 to ~15 m/s scale
    final progress = (velocity / 15.0).clamp(0.0, 1.0);
    final activeSegments = (progress * 8).round();

    return _SpaceUiGaugeBox(
      label: 'LAUNCH SPEED',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                velocity.toStringAsFixed(1),
                style: GoogleFonts.orbitron(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 3),
              Text(
                'm/s',
                style: GoogleFonts.orbitron(
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF00E5FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 8-segment LED meter bar
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(8, (index) {
              final isActive = index < activeSegments;
              Color segColor;
              if (index < 4) {
                segColor = const Color(0xFF00E5FF); // Cyan
              } else if (index < 6) {
                segColor = const Color(0xFFFFD600); // Amber
              } else {
                segColor = const Color(0xFFFF3D00); // Hot red
              }

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                width: 6,
                height: 7,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1.5),
                  color: isActive ? segColor : segColor.withValues(alpha: 0.15),
                  boxShadow: isActive
                      ? [BoxShadow(color: segColor.withValues(alpha: 0.7), blurRadius: 4)]
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Kenney Space UI Trajectory Angle Gauge
// ─────────────────────────────────────────────────────────────────────────────
class _SpaceUiAngleGauge extends StatelessWidget {
  final double angle;

  const _SpaceUiAngleGauge({required this.angle});

  @override
  Widget build(BuildContext context) {
    // Clamped deflection from -45° to +45°
    final normalized = (angle / 45.0).clamp(-1.0, 1.0);

    return _SpaceUiGaugeBox(
      label: 'TRAJECTORY',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${angle >= 0 ? '+' : ''}${angle.toStringAsFixed(1)}',
                style: GoogleFonts.orbitron(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                '°',
                style: GoogleFonts.orbitron(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF00E5FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Visual Horizon Vector Meter
          SizedBox(
            height: 7,
            width: 65,
            child: CustomPaint(
              painter: _VectorMeterPainter(normalized: normalized),
            ),
          ),
        ],
      ),
    );
  }
}

class _VectorMeterPainter extends CustomPainter {
  final double normalized; // -1.0 to 1.0

  _VectorMeterPainter({required this.normalized});

  @override
  void paint(Canvas canvas, Size size) {
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), trackPaint);

    // Center zero mark
    final centerPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.8)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), centerPaint);

    // Deflection indicator pip
    final pipX = (size.width / 2) + (normalized * (size.width / 2 - 4));
    final pipPaint = Paint()
      ..color = const Color(0xFFFF9100)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(pipX, size.height / 2), 3.5, pipPaint);
  }

  @override
  bool shouldRepaint(covariant _VectorMeterPainter oldDelegate) =>
      oldDelegate.normalized != normalized;
}

// ─────────────────────────────────────────────────────────────────────────────
// Kenney Space UI Remaining Shots Counter
// ─────────────────────────────────────────────────────────────────────────────
class _SpaceUiShotsGauge extends StatelessWidget {
  final int remainingShots;

  const _SpaceUiShotsGauge({required this.remainingShots});

  @override
  Widget build(BuildContext context) {
    return _SpaceUiGaugeBox(
      label: 'REMAINING',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$remainingShots',
                style: GoogleFonts.orbitron(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                '/4',
                style: GoogleFonts.orbitron(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 4 Puck Ammo Pips
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(4, (index) {
              final isReady = index < remainingShots;
              const cellColor = Color(0xFF00E5FF);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isReady ? cellColor : Colors.white10,
                  border: Border.all(
                    color: isReady ? Colors.white : Colors.white24,
                    width: 1,
                  ),
                  boxShadow: isReady
                      ? [BoxShadow(color: cellColor.withValues(alpha: 0.8), blurRadius: 4)]
                      : null,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Kenney Space UI Chamfered Frame Container
// ─────────────────────────────────────────────────────────────────────────────
class _SpaceUiGaugeBox extends StatelessWidget {
  final String label;
  final Widget child;

  const _SpaceUiGaugeBox({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x99111827),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF1E293B), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.orbitron(
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF00E5FF).withValues(alpha: 0.85),
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Turn Countdown Timer
// ─────────────────────────────────────────────────────────────────────────────
class _TurnCountdownTimer extends ConsumerStatefulWidget {
  final String sessionId;
  const _TurnCountdownTimer({required this.sessionId});

  @override
  ConsumerState<_TurnCountdownTimer> createState() => _TurnCountdownTimerState();
}

class _TurnCountdownTimerState extends ConsumerState<_TurnCountdownTimer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int _secondsLeft = 15;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      _updateTimer();
    });
    _ticker.start();
  }

  void _updateTimer() {
    final sessionState = ref.read(gameSessionProvider(widget.sessionId)).value;
    if (sessionState == null) return;
    
    if (sessionState.status != 'active') {
      if (_secondsLeft != 0) setState(() => _secondsLeft = 0);
      return;
    }

    final startTime = sessionState.turnStartedAt ?? DateTime.now();
    final elapsed = DateTime.now().difference(startTime.toLocal()).inSeconds;
    final remaining = 15 - elapsed;
    
    if (remaining != _secondsLeft) {
      setState(() {
        _secondsLeft = remaining.clamp(0, 15);
      });
    }
  }
  
  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWarning = _secondsLeft <= 5;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isWarning ? Colors.red.withValues(alpha: 0.2) : const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isWarning ? Colors.red : Colors.white30, width: 2),
      ),
      child: Text(
        '$_secondsLeft s',
        style: GoogleFonts.orbitron(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isWarning ? Colors.red : Colors.white70,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Waiting Overlay — shown before game starts
// ─────────────────────────────────────────────────────────────────────────────
class _WaitingOverlay extends StatelessWidget {
  const _WaitingOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: PukHukTheme.surface.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'WAITING FOR OPPONENT',
              style: GoogleFonts.orbitron(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: PukHukTheme.primary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: PukHukTheme.primary),
          ],
        ),
      ),
    ).animate(onPlay: (c) => c.repeat(reverse: true)).fade(
          begin: 0.8,
          end: 1.0,
          duration: 1000.ms,
        );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pause Button
// ─────────────────────────────────────────────────────────────────────────────
class _PauseButton extends ConsumerWidget {
  final String sessionId;
  final String localPlayerId;
  final int pausesUsed;
  final bool isPaused;

  const _PauseButton({
    required this.sessionId,
    required this.localPlayerId,
    required this.pausesUsed,
    required this.isPaused,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPauses = pausesUsed < 3;
    final color = isPaused ? Colors.amber : (hasPauses ? Colors.white70 : Colors.white24);

    return InkWell(
      onTap: () {
        if (!hasPauses && !isPaused) return;
        
        final sessionState = ref.read(gameSessionProvider(sessionId)).value;
        if (sessionState == null) return;

        final syncService = ref.read(realtimeSyncServiceProvider);
        
        if (isPaused) {
          syncService.submitTurn(
            matchId: sessionId,
            playerId: localPlayerId,
            expectedTurnNumber: sessionState.turnNumber,
            newState: sessionState.copyWith(
              status: 'active',
              turnStartedAt: DateTime.now().toUtc(),
            ),
          );
        } else {
          final newPauses = Map<String, int>.from(sessionState.pausesUsed);
          newPauses[localPlayerId] = pausesUsed + 1;

          syncService.submitTurn(
            matchId: sessionId,
            playerId: localPlayerId,
            expectedTurnNumber: sessionState.turnNumber,
            newState: sessionState.copyWith(
              status: 'paused',
              pausesUsed: newPauses,
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(isPaused ? Icons.play_arrow : Icons.pause, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              isPaused ? 'RESUME' : 'PAUSE',
              style: GoogleFonts.orbitron(color: color, fontSize: 10, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < (3 - pausesUsed) ? Colors.greenAccent : Colors.redAccent.withValues(alpha: 0.5),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
