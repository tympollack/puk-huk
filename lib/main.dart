import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';
import 'core/services/sso_auth_helper.dart';
import 'core/supabase_config.dart';
import 'core/theme/puk_huk_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to landscape — shuffleboard is a horizontal game
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: PukHukTheme.surface,
  ));

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  try {
    await SsoAuthHelper.hydrateOnStartup(
      client: Supabase.instance.client,
      supabaseUrl: SupabaseConfig.url,
    );
  } catch (e) {
    debugPrint('[Main] SSO startup hydration error: $e');
  }

  runApp(const ProviderScope(child: PukHukApp()));
}

class PukHukApp extends ConsumerWidget {
  const PukHukApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Puk Huk',
      theme: PukHukTheme.dark(),
      darkTheme: PukHukTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
