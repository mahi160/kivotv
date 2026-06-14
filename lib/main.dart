import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'providers/bootstrap_provider.dart';
import 'routes/app_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: KivoApp()));
}

class KivoApp extends ConsumerWidget {
  const KivoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrap = ref.watch(bootstrapProvider);

    return MaterialApp.router(
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
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
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo mark
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  colors: [AppColors.logoGradientStart, AppColors.logoGradientEnd],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.logoGradientStart.withValues(alpha: 0.4),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.live_tv_rounded,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Kivo',
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Live TV launcher',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.darkOnSurfaceVariant,
              ),
            ),
            const SizedBox(height: 48),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.oceanBright,
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
