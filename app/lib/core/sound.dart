import 'dart:async';

import 'dart:io' show Platform;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'armies.dart';
import 'settings_store.dart';

/// Sound effects (docs/AUDIO.md). Short sounds go through small player pools so
/// overlapping effects never cut each other off.
class SoundService {
  SoundService(this.settings);

  final SettingsStore settings;
  final _pools = <String, AudioPool>{};
  bool muted = false;

  static const _sfx = {
    'ui_tap',
    'ui_back',
    'ui_toggle',
    'ui_error',
    'army_select',
    'ready',
    'match_found',
    'question_show',
    'tick',
    'answer_locked',
    'other_answered',
    'correct',
    'wrong',
    'time_up',
    'claim',
    'march',
    'battle_start',
    'round_start',
    'sword_swing',
    'sword_clash',
    'battle_impact',
    'base_guarded',
    'tower_hit',
    'eliminated',
    'powerup',
    'coins',
    'victory',
    'defeat',
    'countdown',
    'your_turn',
    'tiebreak',
    'extra_turn',
    'remove_two',
    'hint',
    'shield',
    'double',
    'ability',
    'player_left',
    'player_back',
    'menu_open',
    'capture_generic',
    'battle_drums',
    'capture_crusader',
    'capture_roman',
    'capture_pharaoh',
    'capture_mongol',
    'capture_ww2',
  };

  Future<AudioPool?> _pool(String asset) async {
    final cached = _pools[asset];
    if (cached != null) return cached;
    try {
      final pool = await AudioPool.createFromAsset(path: asset, maxPlayers: 3);
      _pools[asset] = pool;
      return pool;
    } catch (_) {
      return null; // missing file or no audio device: stay silent
    }
  }

  Future<void> play(String id) async {
    if (muted || settings.sfxVolume <= 0) return;
    final asset = _sfx.contains(id) ? 'audio/sfx/$id.ogg' : null;
    if (asset == null) return;
    final pool = await _pool(asset);
    await pool?.start(volume: settings.sfxVolume);
  }

  /// The capturing army's war cry: the takbir for the three Islamic armies.
  Future<void> capture(String army) async {
    if (muted || settings.sfxVolume <= 0) return;
    if (islamicArmies.contains(army)) {
      final pool = await _pool('audio/private/takbir.ogg');
      if (pool != null) {
        await pool.start(volume: settings.sfxVolume);
        return;
      }
      return play('capture_generic');
    }
    final id = 'capture_$army';
    return play(_sfx.contains(id) ? id : 'capture_generic');
  }

  // ------------------------------------------------------------------ music

  // widget tests have no audio plugin
  static final bool _testing = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  final _decks = <AudioPlayer>[];
  int _deck = 0;
  String? _track;

  /// Play a looping music bed ('menu', 'map', 'battle') or stop (null), crossfading 1.5 s.
  /// Calling it again with the same track does nothing.
  Future<void> music(String? track) async {
    if (track == _track) return;
    _track = track;
    if (_testing) return;
    try {
      if (_decks.isEmpty) _decks.addAll([AudioPlayer(), AudioPlayer()]);
      final old = _decks[_deck];
      _deck = 1 - _deck;
      final next = _decks[_deck];
      final vol = muted ? 0.0 : settings.musicVolume * 0.7;
      _fade(old, to: 0, then: old.stop);
      if (track == null || vol <= 0) return;
      await next.setReleaseMode(ReleaseMode.loop);
      await next.setVolume(0);
      await next.play(AssetSource('audio/music/$track.ogg'));
      _fade(next, to: vol);
    } catch (_) {
      _track = null; // e.g. the browser blocks audio before the first tap: try again next time
    }
  }

  /// Follow a new music volume from the settings right away.
  Future<void> musicVolumeChanged() async {
    if (_decks.isEmpty || _track == null) return;
    await _decks[_deck].setVolume(muted ? 0 : settings.musicVolume * 0.7);
  }

  void _fade(AudioPlayer p, {required double to, Future<void> Function()? then}) {
    final from = p.volume;
    var step = 0;
    Timer.periodic(const Duration(milliseconds: 100), (t) {
      step++;
      final v = from + (to - from) * (step / 15);
      p.setVolume(v.clamp(0, 1)).catchError((_) {});
      if (step >= 15) {
        t.cancel();
        then?.call().catchError((_) {});
      }
    });
  }

  /// Warm the pools used in a match so the first sounds are not late on slow phones.
  Future<void> preload() async {
    for (final id in ['question_show', 'tick', 'answer_locked', 'correct', 'wrong', 'claim', 'sword_clash']) {
      await _pool('audio/sfx/$id.ogg');
    }
  }
}

final soundProvider = Provider<SoundService>((ref) {
  AudioCache.instance = AudioCache(prefix: 'assets/');
  return SoundService(ref.watch(settingsProvider));
});
