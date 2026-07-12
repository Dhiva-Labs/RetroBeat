import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';

/// Shown while the library loads.
///
/// Quiet on purpose: a splash that bounces and glows is a splash you notice,
/// and the goal is for the user to reach their music without noticing anything.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 56,
              color: scheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              AppConstants.appName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
