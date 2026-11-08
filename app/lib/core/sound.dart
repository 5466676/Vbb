import 'dart:async';
import 'dart:math';

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

  Future<void> play(String id, {double volume = 1}) async {
    if (muted || settings.sfxVolume <= 0) return;
    final asset = _sfx.contains(id) ? 'audio/sfx/$id.ogg' : null;
    if (asset == null) return;
    final pool = await _pool(asset);
    await pool?.start(volume: settings.sfxVolume * volume);
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
  int _part = 0;
  StreamSubscription<void>? _partEnd;

  /// Tracks made of several pieces play them in turn, starting at a random one. The four war
  /// loops play in the menus and, mixed with the match beds, during the match.
  static const _musicParts = {
    'menu': ['menu_1', 'menu_2', 'menu_3', 'menu_4'],
    'map': ['menu_2', 'menu_3', 'map'], // expansion: battle preparation, eastern war
    'battle': ['menu_1', 'menu_4', 'battle'], // battle: war anthem, modern war
  };

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
      await _partEnd?.cancel();
      _partEnd = null;
      await next.setVolume(0);
      final parts = _musicParts[track];
      if (parts == null) {
        await next.setReleaseMode(ReleaseMode.loop);
        await next.play(AssetSource('audio/music/$track.ogg'));
      } else {
        // a playlist: each piece once, then the next, round and round
        _part = _rnd.nextInt(parts.length);
        await next.setReleaseMode(ReleaseMode.stop);
        await next.play(AssetSource('audio/music/${parts[_part]}.ogg'));
        _partEnd = next.onPlayerComplete.listen((_) {
          if (_track != track) return;
          _part = (_part + 1) % parts.length;
          next.play(AssetSource('audio/music/${parts[_part]}.ogg')).catchError((_) {});
        });
      }
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

  // ------------------------------------------------------------------ commentator

  /// Levantine commentator lines (`assets/audio/voice/<id>_<n>.ogg`), variants picked at random.
  static const _voiceVariants = {
    'start': 2,
    'castles': 1,
    'expansion': 1,
    'your_turn': 2,
    'duel': 2,
    'capture': 2,
    'held': 2,
    'tower': 1,
    'last_tower': 1,
    'eliminated': 1,
    'tiebreak': 1,
    'final_round': 1,
    'hurry': 1,
    'too_slow': 1,
    'treasure': 1,
    'fastest': 1,
    'lead': 1,
    'victory': 2,
    'defeat': 1,
  };
  AudioPlayer? _voice;
  DateTime _voiceUntil = DateTime(2000);
  final _rnd = Random();

  /// Say a line (with probability [chance], so frequent events do not tire). A new line does not
  /// cut one still playing; music ducks while the commentator talks.
  Future<void> say(String id, {double chance = 1}) async {
    final n = _voiceVariants[id];
    if (n == null || muted || settings.voiceVolume <= 0 || _testing) return;
    if (_rnd.nextDouble() > chance || DateTime.now().isBefore(_voiceUntil)) return;
    _voiceUntil = DateTime.now().add(const Duration(milliseconds: 1800));
    try {
      _voice ??= AudioPlayer();
      await _voice!.setVolume(settings.voiceVolume);
      await _voice!.play(AssetSource('audio/voice/${id}_${1 + _rnd.nextInt(n)}.ogg'));
      _duck();
    } catch (_) {
      // no audio device / file: stay silent
    }
  }

  void _duck() {
    if (_decks.isEmpty || _track == null) return;
    final deck = _decks[_deck];
    final full = muted ? 0.0 : settings.musicVolume * 0.7;
    deck.setVolume(full * 0.4).catchError((_) {});
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (_track != null) deck.setVolume(full).catchError((_) {});
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
