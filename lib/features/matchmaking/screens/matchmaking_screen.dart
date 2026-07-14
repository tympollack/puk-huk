import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:async';

import '../../../core/providers/auth_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/puk_huk_theme.dart';
import '../../../services/matchmaking_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MatchmakingScreen — initiates queue search, shows live wait time +
// expanding ELO tolerance, navigates to GameScreen on match found.
// ─────────────────────────────────────────────────────────────────────────────
class MatchmakingScreen extends ConsumerStatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  ConsumerState<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends ConsumerState<MatchmakingScreen> {
  MatchmakingState _state = const MatchmakingState();
  StreamSubscription<MatchmakingState>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSearch());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _startSearch() {
    final player = ref.read(currentPlayerProvider).value;
    if (player == null) return;

    final service = ref.read(matchmakingServiceProvider);
    _sub = service.joinQueue(player).listen((state) {
      if (!mounted) return;
      setState(() => _state = state);

      if (state.status == MatchmakingStatus.found && state.sessionId != null) {
        context.pushReplacement(Routes.gameWithId(state.sessionId!));
      }
    });
  }

  void _cancelSearch() {
    final player = ref.read(currentPlayerProvider).value;
    if (player != null) {
      ref.read(matchmakingServiceProvider).leaveQueue(player.uid);
    }
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FINDING MATCH')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 90,
              height: 90,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: PukHukTheme.primary,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _statusLabel(),
              style: GoogleFonts.orbitron(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: PukHukTheme.textPrimary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_state.waitTime.inSeconds}s elapsed · ELO range ±${_state.currentEloTolerance}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 40),
            OutlinedButton(
              onPressed: _cancelSearch,
              child: const Text('CANCEL'),
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel() {
    switch (_state.status) {
      case MatchmakingStatus.searching:
        return 'SEARCHING FOR OPPONENT...';
      case MatchmakingStatus.found:
        return 'MATCH FOUND!';
      case MatchmakingStatus.timeout:
        return 'NO OPPONENTS FOUND';
      case MatchmakingStatus.error:
        return 'SOMETHING WENT WRONG';
      case MatchmakingStatus.idle:
        return 'PREPARING...';
    }
  }
}
