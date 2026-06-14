import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/theme/app_theme.dart';
import 'routes/app_router.dart';
import 'services/playlist_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: KivoApp()));
  PlaylistRepository.instance.bootstrap().catchError((
    Object error,
    StackTrace stackTrace,
  ) {
    debugPrint('Playlist bootstrap failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  });
}

class KivoApp extends StatelessWidget {
  const KivoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
    );
  }
}
