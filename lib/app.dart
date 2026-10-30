import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';
import 'features/auth/auth_screen.dart';
import 'features/playbook/playbook_screen.dart';

class PlaybookApp extends ConsumerWidget {
  const PlaybookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    return MaterialApp(
      title: 'PlaybookAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2E7D32), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: switch (session) {
        SignedOut() => const AuthScreen(),
        _ => const PlaybookScreen(),
      },
    );
  }
}
