import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Device storage for offline play: the downloaded solo questions and the actions waiting
/// to be synced (`pending_actions`). SQLite on the phone; in memory in a web build.
class LocalStore {
  LocalStore._(this._db);

  final Database? _db;
  final Map<String, Map<String, dynamic>> _memQuestions = {};
  final Map<String, Map<String, dynamic>> _memPending = {};

  /// In-memory store (web builds and tests).
  factory LocalStore.memory() => LocalStore._(null);

  static Future<LocalStore> open() async {
    if (kIsWeb) return LocalStore._(null);
    final db = await openDatabase(
      p.join(await getDatabasesPath(), 'harb.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE questions (id TEXT PRIMARY KEY, category TEXT, json TEXT NOT NULL)');
        await db.execute('CREATE TABLE pending_actions (id TEXT PRIMARY KEY, ts TEXT NOT NULL, json TEXT NOT NULL)');
      },
    );
    return LocalStore._(db);
  }

  /// Apply a page from `GET /questions` or `/sync`: upserts and tombstones.
  Future<void> applyQuestions(List<dynamic> items) async {
    for (final raw in items) {
      final q = (raw as Map).cast<String, dynamic>();
      final id = q['id'] as String;
      if (q['deleted'] == true) {
        _memQuestions.remove(id);
        await _db?.delete('questions', where: 'id = ?', whereArgs: [id]);
      } else {
        _memQuestions[id] = q;
        await _db?.insert('questions', {
          'id': id,
          'category': q['category'],
          'json': jsonEncode(q),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<List<Map<String, dynamic>>> questions({String? category}) async {
    final db = _db;
    if (db == null) {
      return _memQuestions.values.where((q) => category == null || q['category'] == category).toList();
    }
    final rows = category == null
        ? await db.query('questions')
        : await db.query('questions', where: 'category = ?', whereArgs: [category]);
    return [for (final r in rows) (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>()];
  }

  Future<int> questionCount() async {
    final db = _db;
    if (db == null) return _memQuestions.length;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM questions')) ?? 0;
  }

  /// Every player action is written here first; [SyncService] sends and clears them.
  Future<void> addPending(Map<String, dynamic> action) async {
    _memPending[action['id'] as String] = action;
    await _db?.insert('pending_actions', {
      'id': action['id'],
      'ts': action['ts'],
      'json': jsonEncode(action),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, dynamic>>> pending({int limit = 500}) async {
    final db = _db;
    if (db == null) return _memPending.values.take(limit).toList();
    final rows = await db.query('pending_actions', orderBy: 'ts', limit: limit);
    return [for (final r in rows) (jsonDecode(r['json'] as String) as Map).cast<String, dynamic>()];
  }

  Future<void> removePending(Iterable<String> ids) async {
    for (final id in ids) {
      _memPending.remove(id);
      await _db?.delete('pending_actions', where: 'id = ?', whereArgs: [id]);
    }
  }
}

final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError('opened in main'));
