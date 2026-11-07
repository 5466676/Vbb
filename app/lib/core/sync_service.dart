import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'local_store.dart';
import 'settings_store.dart';

/// Sends pending actions and fetches question updates when the server is reachable.
/// Never throws and never blocks play: if the server is off it just tries again later
/// (on app start and when an online screen opens).
class SyncService {
  SyncService(this.api, this.store, this.settings);

  final Api api;
  final LocalStore store;
  final SettingsStore settings;
  bool _running = false;
  Map<String, dynamic>? lastStats;

  Future<bool> sync() async {
    if (_running || settings.serverUrl.isEmpty) return false;
    _running = true;
    try {
      if (!await api.health()) return false;
      var since = settings.questionsVersion;
      for (var round = 0; round < 20; round++) {
        final pending = await store.pending();
        final res = await api.sync(pending, since);
        // every action that came back with a status is done, whatever the status
        await store.removePending([for (final r in res['results'] as List) r['id'] as String]);
        lastStats = (res['stats'] as Map?)?.cast<String, dynamic>();
        final q = (res['questions'] as Map?)?.cast<String, dynamic>();
        if (q != null) {
          await store.applyQuestions(q['items'] as List);
          since = q['version'] as int;
          await settings.setQuestionsVersion(since);
        }
        final morePending = pending.length >= 500;
        final moreQuestions = q?['more'] == true;
        if (!morePending && !moreQuestions) break;
      }
      return true;
    } catch (_) {
      return false; // try again later
    } finally {
      _running = false;
    }
  }
}

final syncProvider = Provider<SyncService>(
  (ref) => SyncService(ref.watch(apiProvider), ref.watch(localStoreProvider), ref.watch(settingsProvider)),
);
