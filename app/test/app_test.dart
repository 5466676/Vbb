import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harb_al_oqool/app/app.dart';
import 'package:harb_al_oqool/app/theme.dart';
import 'package:harb_al_oqool/core/api.dart';
import 'package:harb_al_oqool/core/local_store.dart';
import 'package:harb_al_oqool/core/map_template.dart';
import 'package:harb_al_oqool/core/settings_store.dart';
import 'package:harb_al_oqool/core/socket.dart';
import 'package:harb_al_oqool/core/sync_service.dart';
import 'package:harb_al_oqool/features/game/game_controller.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SettingsStore> _settings([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsStore.open();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('server links are normalised', () {
    expect(normalizeServerUrl(' pc.tail.ts.net/ '), 'https://pc.tail.ts.net');
    expect(normalizeServerUrl('http://192.168.1.5:8080'), 'http://192.168.1.5:8080');
    expect(normalizeServerUrl(''), '');
  });

  test('the device keeps one permanent UUID', () async {
    final s = await _settings();
    final id = s.deviceId;
    expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(id), isTrue);
    expect(s.deviceId, id);
  });

  test('theme: old-map palette and the Cairo font', () {
    final theme = AppTheme.dark();
    expect(theme.colorScheme.primary, AppColors.gold);
    expect(theme.textTheme.bodyMedium?.fontFamily, 'Cairo');
    expect(AppColors.seats.toSet().length, 8);
  });

  group('sync', () {
    test('sends pending actions, removes only those the server answered, keeps questions', () async {
      final s = await _settings({'server_url': 'https://srv', 'token': 't', 'player_id': 'p'});
      final store = LocalStore.memory();
      for (final id in ['a1', 'a2', 'a3']) {
        await store.addPending({'id': id, 'type': 'answer', 'ts': '2026-11-07T10:00:00+00:00'});
      }
      final sent = <List>[];
      final client = MockClient((req) async {
        if (req.url.path == '/health') return http.Response('{"status":"ok"}', 200);
        final body = jsonDecode(req.body) as Map;
        sent.add(body['actions'] as List);
        // the server answers a1 (ok) and a2 (duplicate); a3 is "lost" this time
        return http.Response(
          jsonEncode({
            'results': [
              {'id': 'a1', 'status': 'ok'},
              {'id': 'a2', 'status': 'duplicate'},
            ],
            'stats': {
              'solo': {'answered': 1},
            },
            'questions': {
              'version': 7,
              'more': false,
              'items': [
                {
                  'id': 'q1',
                  'version': 7,
                  'deleted': false,
                  'kind': 'mcq',
                  'text': 'س؟',
                  'options': ['أ', 'ب', 'ج', 'د'],
                  'correct_index': 0,
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final sync = SyncService(Api(s, client: client), store, s);
      expect(await sync.sync(), isTrue);
      expect(sent.single.map((a) => a['id']), ['a1', 'a2', 'a3']);
      expect((await store.pending()).map((a) => a['id']), ['a3'], reason: 'unanswered actions are kept and retried');
      expect(await store.questionCount(), 1);
      expect(s.questionsVersion, 7);

      // a deletion (tombstone) removes the question from the device
      await store.applyQuestions([
        {'id': 'q1', 'version': 8, 'deleted': true},
      ]);
      expect(await store.questionCount(), 0);
    });

    test('server off: nothing is lost and nothing throws', () async {
      final s = await _settings({'server_url': 'https://srv', 'token': 't'});
      final store = LocalStore.memory();
      await store.addPending({'id': 'x', 'type': 'answer', 'ts': '2026-11-07T10:00:00+00:00'});
      final client = MockClient((req) async => throw Exception('connection refused'));
      expect(await SyncService(Api(s, client: client), store, s).sync(), isFalse);
      expect((await store.pending()).length, 1);
    });
  });

  test('map templates load and territories are hit-tested', () async {
    final t = await MapTemplate.load('fantasy-4p');
    expect(t.territories, isNotEmpty);
    expect(t.bases.length, 4);
    final first = t.territories.first;
    expect(first.contains(first.label), isTrue, reason: 'the label point lies inside its territory');
    expect(first.contains(const Offset(-1, -1)), isFalse);
  });

  test('the game controller builds the match from server events', () async {
    final s = await _settings({'server_url': 'https://srv', 'token': 't', 'player_id': 'me'});
    final c = ProviderContainer(overrides: [settingsProvider.overrideWithValue(s)]);
    addTearDown(c.dispose);
    final game = c.read(gameProvider.notifier);
    game.sound.muted = true;
    game.handle(
      ServerMessage('room_state', {
        'code': 'ABCDEF',
        'host': 'me',
        'status': 'playing',
        'settings': {'mode': 'ffa'},
        'seats': [
          {'seat': 0, 'player_id': 'me', 'name': 'سامي', 'army': 'roman', 'ready': true},
          {'seat': 1, 'player_id': null, 'name': 'بوت', 'army': 'mongol', 'ready': true, 'bot': 'easy'},
        ],
        'votes': {},
      }),
    );
    game.handle(
      ServerMessage('match_started', {
        'map_id': 'fantasy-2p',
        'map_kind': 'fantasy',
        'mode': 'ffa',
        'rounds': 19,
        'base_towers': 5,
        'players': [
          {'seat': 0, 'name': 'سامي', 'army': 'roman', 'team': 0, 'bot': false},
          {'seat': 1, 'name': 'بوت', 'army': 'mongol', 'team': 1, 'bot': true},
        ],
        'bases': [2, 1],
      }),
    );
    var m = c.read(gameProvider).match!;
    expect(m.mySeat, 0);
    expect(m.territories[2]!.isBase && m.territories[2]!.towers == 5, isTrue);

    game.handle(
      ServerMessage('question', {
        'id': 'q9',
        'kind': 'mcq',
        'text': 'سؤال؟',
        'unit': '',
        'options': ['1', '2', '3', '4'],
        'participant': true,
        'participants': [0, 1],
        'time_ms': 15000,
        'phase_id': 3,
      }),
    );
    game.handle(ServerMessage('answer_locked', {'seat': 1}));
    game.handle(
      ServerMessage('question_result', {
        'id': 'q9',
        'correct_index': 2,
        'ranking': [1, 0],
        'answers': {},
      }),
    );
    game.handle(ServerMessage('territory_claimed', {'seat': 0, 'territory': 5, 'auto': false, 'value': 200}));
    game.handle(
      ServerMessage('phase_changed', {
        'phase': 'battle_target',
        'phase_id': 9,
        'opens_in_ms': 0,
        'deadline_ms': 8000,
        'attacker': 0,
        'round': 1,
        'targets': [1, 3],
      }),
    );
    m = c.read(gameProvider).match!;
    expect(m.question, isNull, reason: 'a new turn clears the old question');
    expect(m.territories[5]!.owner, 0);
    expect(m.myTurn, isTrue);
    expect(m.targets, [1, 3]);

    game.handle(ServerMessage('territory_captured', {'territory': 1, 'attacker': 0, 'defender': 1, 'value': 1100}));
    game.handle(
      ServerMessage('match_ended', {
        'winner_team': 0,
        'standings': [
          {'seat': 0, 'team': 0, 'score': 2500, 'correct': 5},
          {'seat': 1, 'team': 1, 'score': 900, 'correct': 2},
        ],
        'team_scores': {'0': 2500, '1': 900},
      }),
    );
    m = c.read(gameProvider).match!;
    expect(m.territories[1]!.owner, 0);
    expect(m.ended, isTrue);
    expect(m.winnerTeam, m.me!.team);
  });

  testWidgets('home screen is Arabic and right-to-left', (tester) async {
    tester.view.physicalSize = const Size(1800, 840);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final s = await _settings();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsProvider.overrideWithValue(s), localStoreProvider.overrideWithValue(LocalStore.memory())],
        child: const HarbApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('العب ضد البوتات (بلا نت)'), findsOneWidget);
    final ctx = tester.element(find.text('العب ضد البوتات (بلا نت)'));
    expect(Directionality.of(ctx), TextDirection.rtl);
  });
}
