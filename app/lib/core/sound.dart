import 'package:audioplayers/audioplayers.dart';
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
