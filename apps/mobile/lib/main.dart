import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:mobile/pages/home_page.dart';
import 'core/controllers/openhab_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/providers/role_provider.dart';
import 'core/providers/installation_provider.dart';
import 'firebase_options.dart';
import 'pages/login_page.dart';
import 'pages/otp_page.dart';
import 'pages/signup_page.dart';
import 'package:mobile/core/services/app_notification_service.dart';

final GoRouter _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/otp',
      builder: (context, state) {
        final email = state.extra as String? ?? '';
        return OtpPage(email: email);
      },
    ),
    GoRoute(
      path: '/signup',
      builder: (context, state) => const SignUpPage(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomePage(),
    ),
  ],
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final roleProvider = RoleProvider();
  final installationProvider = InstallationProvider();
  if (FirebaseAuth.instance.currentUser != null) {
    await roleProvider.loadRole();
    await installationProvider.load();
    if (installationProvider.config != null) {
      await OpenHABController.instance
          .initializeWithConfig(installationProvider.config!);
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: roleProvider),
        ChangeNotifierProvider.value(value: installationProvider),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'Philoin Smarthome',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          scaffoldMessengerKey: AppNotificationService.messengerKey,
          routerConfig: _router,
        );
      },
    );
  }
}