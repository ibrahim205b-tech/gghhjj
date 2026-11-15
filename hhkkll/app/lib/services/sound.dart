import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

enum Sfx {
  introBoom('intro_boom'),
  introWhoosh('intro_whoosh'),
  introRise('intro_rise'),
  introHit('intro_hit'),
  start('start'),
  question('question'),
  tick('tick'),
  tickLast('tick_last'),
  go('go'),
  buzzer('buzzer'),
  correct('correct'),
  wrong('wrong'),
  strike('strike'),
  eliminated('eliminated'),
  auctionWin('auction_win'),
  bid('bid'),
  reveal('reveal'),
  pass('pass'),
  winner('winner');

  const Sfx(this.file);
  final String file;
}

/// Plays the synthesised effects. One player per effect so overlapping
/// effects (tick + buzzer) do not cut each other off.
class SoundService {
  SoundService({this.enabled = true});

  /// False in widget tests (no audio platform).
  final bool enabled;
  double volume = 0.9;
  bool muted = false;
  final Map<Sfx, AudioPlayer> _players = {};

  /// Every effect played, for tests and diagnostics.
  final List<Sfx> played = [];

  Future<void> preload() async {
    if (!enabled) return;
    for (final s in Sfx.values) {
      try {
        final p = AudioPlayer(playerId: 'sfx-${s.file}');
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        await p.setSource(AssetSource('sounds/${s.file}.wav'));
        _players[s] = p;
      } catch (e) {
        debugPrint('sound preload failed for ${s.file}: $e');
      }
    }
  }

  void play(Sfx s) {
    played.add(s);
    if (!enabled || muted || volume <= 0) return;
    final p = _players[s];
    if (p == null) return;
    () async {
      try {
        await p.stop();
        await p.setVolume(volume);
        await p.resume();
      } catch (e) {
        debugPrint('sound ${s.file}: $e');
      }
    }();
  }

  Future<void> stopAll() async {
    for (final p in _players.values) {
      try {
        await p.stop();
      } catch (_) {}
    }
  }
}
