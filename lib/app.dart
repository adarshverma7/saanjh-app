import 'package:flutter/material.dart';

import 'frontend/router/app_router.dart';
import 'frontend/theme/app_theme.dart';

class SaanjhApp extends StatelessWidget {
  const SaanjhApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Saanjh',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      routerConfig: AppRouter.router,
    );
  }
}
