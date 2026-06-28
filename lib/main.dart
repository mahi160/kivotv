import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/kivo_logo.dart';
import 'providers/bootstrap_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'core/router/app_router.dart';
import 'providers/repository_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};

  // Cap the Flutter image cache so channel logos don't exhaust RAM on
  // low-end Android TV boxes (1 GB RAM) that also buffer video.
  PaintingBinding.instance.imageCache
    ..maximumSize = 150
    ..maximumSizeBytes = 48 << 20; // 48 MB

  runApp(const ProviderScope(child: KivoApp()));
}

// ─────────────────────────────────────────────────────────────────────────────
//  App root
// ─────────────────────────────────────────────────────────────────────────────

class KivoApp extends ConsumerStatefulWidget {
  const KivoApp({super.key});

  @override
  ConsumerState<KivoApp> createState() => _KivoAppState();
}

class _KivoAppState extends ConsumerState<KivoApp> with WidgetsBindingObserver {
  // Ensures the auto-open navigation fires exactly once per app session,
  // not on every rebuild triggered by theme changes etc.
  bool _autoOpenDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Skip the tflix scrape when the player is active — it triggers a
    // network fetch + DB write that contends with live video decode on 1 GB
    // Android TV SoCs. The 2-min staleness guard prevents storms on
    // quick player⇄home bounces; the home screen re-scrapes on next open.
    try {
      final path = appRouter.routerDelegate.currentConfiguration.uri.path;
      if (path == '/player') return;
    } catch (_) {
      // Router not yet initialised — safe to proceed.
    }
    ref.read(repositoryProvider).refreshTflixMatches();
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(bootstrapProvider);

    // As soon as bootstrap completes, try to resume the last watched channel.
    // First-launch has no recently watched → stays on home. Subsequent
    // launches open the player immediately.
    if (!_autoOpenDone && bootstrap is AsyncData) {
      _autoOpenDone = true;
      // Defer one frame so the router widget is in the tree, then pass the
      // live BuildContext so navigation uses the mounted navigator.
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpen());
    }

    // Map the TV remote SELECT / OK key to ActivateIntent at the app root.
    // This makes every Material button respond to the remote select key
    // without custom onKeyEvent handlers in individual widgets.
    // Fixed cinematic palette (no Material You / dynamic colour) so the brand
    // look is identical on every device. Theme mode is a persisted user choice.
    final themeMode = ref.watch(themeModeProvider);

    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      child: MaterialApp.router(
        routerConfig: appRouter,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) {
          // TV UIs are pre-sized for 10-foot viewing; accessibility text scale
          // should not apply or it will overflow fixed-height cards and rows.
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 1.0,
                maxScaleFactor: 1.0,
              ),
            ),
            child: bootstrap.when(
              data: (_) => child!,
              error: (err, _) => _BootstrapError(error: err),
              loading: () => const _SplashScreen(),
            ),
          );
        },
      ),
    );
  }

  Future<void> _autoOpen() async {
    // Only auto-resume if the user was watching within the last 24 hours.
    // A cold install or long-idle device should start at Home, not jump
    // straight into a stream the user may have forgotten about.
    final lastWatched = await ref.read(repositoryProvider).lastWatchedAt();
    if (!mounted || lastWatched == null) return;
    if (DateTime.now().difference(lastWatched) > const Duration(hours: 24)) return;

    final recent = await ref.read(repositoryProvider).recentlyWatched();
    if (!mounted || recent.isEmpty) return;
    try {
      final currentPath =
          appRouter.routerDelegate.currentConfiguration.uri.path;
      if (currentPath != '/') return;
      // push (not go) so back from the player returns to Home.
      appRouter.push('/player', extra: {'channel': recent.first});
    } catch (_) {
      // Router not yet ready — shouldn't happen post-bootstrap, but safe.
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Splash screen
// ─────────────────────────────────────────────────────────────────────────────

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KivoLogo(size: 100),
            const SizedBox(height: 28),
            Text('Kivo', style: Theme.of(context).textTheme.displayLarge),
            const SizedBox(height: 8),
            Text(
              'Live TV launcher',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: 280,
              child: LinearProgressIndicator(
                backgroundColor: AppColors.oceanDeepBlue.withValues(
                  alpha: 0.20,
                ),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  AppColors.goldenDriftwood,
                ),
                minHeight: 4,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Starting up…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.oceanDeepBlue.withValues(alpha: 0.60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Bootstrap error screen
// ─────────────────────────────────────────────────────────────────────────────

class _BootstrapError extends StatelessWidget {
  const _BootstrapError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 64,
                color: AppColors.error,
              ),
              const SizedBox(height: 24),
              Text(
                'Failed to start Kivo',
                style: Theme.of(
                  context,
                ).textTheme.headlineMedium?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Database could not be initialised.\n$error',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.darkOnSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
