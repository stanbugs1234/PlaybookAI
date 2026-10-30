import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/play.dart';
import '../models/starter_plays.dart';

abstract class PlayRepository {
  Stream<List<Play>> watch();
  Future<void> save(Play play);
  Future<void> delete(String id);
}

List<Play> _sorted(Iterable<Play> plays) =>
    plays.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

/// Plays stored on this device (guest mode, or when Firebase isn't set up).
class LocalPlayRepository implements PlayRepository {
  static const _key = 'plays_v1';
  final _controller = StreamController<List<Play>>.broadcast();
  Map<String, Play>? _cache;

  Future<Map<String, Play>> _load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) {
      _cache = {for (final p in StarterPlays.all()) p.id: p};
      await _persist();
    } else {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      _cache = {for (final j in list) j['id'] as String: Play.fromJson(j)};
    }
    return _cache!;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(_cache!.values.map((p) => p.toJson()).toList()));
    _controller.add(_sorted(_cache!.values));
  }

  @override
  Stream<List<Play>> watch() async* {
    yield _sorted((await _load()).values);
    yield* _controller.stream;
  }

  @override
  Future<void> save(Play play) async {
    (await _load())[play.id] = play;
    await _persist();
  }

  @override
  Future<void> delete(String id) async {
    (await _load()).remove(id);
    await _persist();
  }
}

/// Plays synced to Firestore under users/{uid}/plays.
class FirestorePlayRepository implements PlayRepository {
  final String uid;
  FirestorePlayRepository(this.uid);

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('plays');

  bool _seeded = false;

  Future<void> _seedIfEmpty() async {
    if (_seeded) return;
    _seeded = true;
    final snap = await _col.limit(1).get();
    if (snap.docs.isNotEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final p in StarterPlays.all()) {
      batch.set(_col.doc(p.id), p.toJson());
    }
    await batch.commit();
  }

  @override
  Stream<List<Play>> watch() async* {
    await _seedIfEmpty();
    yield* _col.snapshots().map((s) => _sorted(s.docs.map((d) {
          try {
            return Play.fromJson(d.data());
          } catch (_) {
            return null;
          }
        }).whereType<Play>()));
  }

  @override
  Future<void> save(Play play) => _col.doc(play.id).set(play.toJson());

  @override
  Future<void> delete(String id) => _col.doc(id).delete();
}
