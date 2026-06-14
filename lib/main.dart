import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/kivo_logo.dart';
import 'providers/bootstrap_provider.dart';
import 'core/router/app_router.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};

  // Cap the Flutter image cache so channel logos don't exhaust RAM on
  // low-end Android TV boxes (1 GB RAM) that also buffer video.
  PaintingBinding.instance.imageCache
    ..maximumSize      = 150
    ..maximumSizeBytes = 48 << 20; // 48 MB

  // Build a temporary container just to hydrate theme before first frame.
  final container = ProviderContainer();
  await container.read(themeModeProvider.notifier).load();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const KivoApp(),
  ));
}

class KivoApp extends ConsumerWidget {
  const KivoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap   = ref.watch(bootstrapProvider);
    final themeMode   = ref.watch(themeModeProvider);

    return MaterialApp.router(
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Show a branded splash until bootstrap completes.
      builder: (context, child) {
        return bootstrap.when(
          // Bootstrap done — render the normal app.
          data: (_) => child!,

          // Bootstrap failed — show error screen instead of blank/crash.
          error: (error, _) => _BootstrapError(error: error),

          // Bootstrap in progress — show branded splash.
          loading: () => const _SplashScreen(),
        );
      },
    );
  }
}

// ── Splash screen ─────────────────────────────────────────────────────────────

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
            // Logo mark
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.oceanDeepBlue,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.oceanDeepBlue.withValues(alpha: 0.45),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(14),
              child: const KivoLogo(),
            ),
            const SizedBox(height: 28),
            Text(
              'Kivo',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Live TV launcher',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 48),
            // Progress bar — wide, thin, and clearly visible on TV.
            SizedBox(
              width: 280,
              child: LinearProgressIndicator(
                backgroundColor:
                    AppColors.oceanDeepBlue.withValues(alpha: 0.20),
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

// ── Bootstrap error screen ────────────────────────────────────────────────────

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
              const Icon(Icons.error_outline_rounded,
                  size: 64, color: AppColors.error),
              const SizedBox(height: 24),
              Text(
                'Failed to start Kivo',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
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
