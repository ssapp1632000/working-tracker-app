import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:window_manager/window_manager.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'services/storage_service.dart';
import 'services/timer_service.dart';
import 'services/logger_service.dart';
import 'services/auth_service.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  final logger = LoggerService();

  // Main window startup
  try {
    logger.info('Starting Work Tracker application...');

    // Load environment variables
    await dotenv.load(fileName: '.env');
    logger.info('Environment variables loaded');

    // Initialize storage service first (needed to check login state)
    final storage = StorageService();
    await storage.initialize();
    logger.info('Storage service initialized');

    // Initialize window manager for desktop
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await windowManager.ensureInitialized();

      // Check if user is logged in to set appropriate window size
      final authService = AuthService();
      final isLoggedIn = authService.isLoggedIn();

      // Auth screens: window IS the card, tight fit
      // Dashboard: larger for new project card UI
      final windowSize = isLoggedIn ? const Size(420, 800) : const Size(420, 400);

      WindowOptions windowOptions = WindowOptions(
        size: windowSize,
        minimumSize: isLoggedIn ? const Size(420, 800) : const Size(420, 400),
        center: true,
        backgroundColor: AppTheme.surfaceColor,
        skipTaskbar: false,
        // Hide native title bar - we use custom WindowControls widget
        titleBarStyle: TitleBarStyle.hidden,
        title: AppConstants.appName,
      );

      await windowManager.waitUntilReadyToShow(
        windowOptions,
        () async {
          // All windows are NON-RESIZABLE
          await windowManager.setResizable(false);
          await windowManager.show();
          await windowManager.focus();
        },
      );

      logger.info('Window initialized with size: ${windowSize.width}x${windowSize.height}');
    }

    // Initialize timer service
    final timerService = TimerService();
    await timerService.initialize();
    logger.info('Timer service initialized');

    // Run main app
    runApp(const ProviderScope(child: MainApp()));
  } catch (e, stackTrace) {
    logger.error(
      'Failed to start application',
      e,
      stackTrace,
    );
    rethrow;
  }
}

/// Main application widget
class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: isLoggedIn ? const DashboardScreen() : const LoginScreen(),
    );
  }
}
