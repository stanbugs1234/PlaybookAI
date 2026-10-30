import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backend.dart';
import '../../data/providers.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool create}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (create) {
        await auth.createUserWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      } else {
        await auth.signInWithEmailAndPassword(
            email: _email.text.trim(), password: _password.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cloud = Backend.firebaseReady;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.sports_football, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('PlaybookAI',
                  textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 4),
              Text('Draw it up. Run it against any defense. Learn the reads.',
                  textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 32),
              if (cloud) ...[
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration:
                      const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(create: false),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: _busy ? null : () => _submit(create: false),
                    child: const Text('Sign in')),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: _busy ? null : () => _submit(create: true),
                    child: const Text('Create account')),
                const SizedBox(height: 24),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('or')),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 16),
              ] else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Cloud sync isn\'t set up yet, so plays are saved on this device. '
                      'Run `flutterfire configure` to enable accounts.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.read(guestModeProvider.notifier).set(true),
                child: Text(cloud ? 'Continue as guest (saved on this device)' : 'Get started'),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
