import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/play.dart';
import 'backend.dart';
import 'play_repository.dart';

/// Who is using the app: a signed-in Firebase user or an on-device guest.
sealed class Session {
  const Session();
}

class SignedOut extends Session {
  const SignedOut();
}

class GuestSession extends Session {
  const GuestSession();
}

class UserSession extends Session {
  final String uid;
  final String? email;
  const UserSession(this.uid, this.email);
}

final authStateProvider = StreamProvider<User?>((ref) {
  if (!Backend.firebaseReady) return Stream.value(null);
  return FirebaseAuth.instance.authStateChanges();
});

class GuestMode extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
}

final guestModeProvider = NotifierProvider<GuestMode, bool>(GuestMode.new);

final sessionProvider = Provider<Session>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user != null) return UserSession(user.uid, user.email);
  if (ref.watch(guestModeProvider)) return const GuestSession();
  return const SignedOut();
});

final playRepositoryProvider = Provider<PlayRepository>((ref) {
  final session = ref.watch(sessionProvider);
  return switch (session) {
    UserSession(:final uid) => FirestorePlayRepository(uid),
    _ => LocalPlayRepository(),
  };
});

final playsProvider = StreamProvider<List<Play>>(
    (ref) => ref.watch(playRepositoryProvider).watch());
