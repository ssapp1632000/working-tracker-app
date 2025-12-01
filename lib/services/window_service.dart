import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'logger_service.dart';

class WindowService {
  static final WindowService _instance =
      WindowService._internal();
  factory WindowService() => _instance;

  final _logger = LoggerService();
  bool _isFloatingMode = false;

  WindowService._internal();

  bool get isFloatingMode => _isFloatingMode;

  // Get current window size
  Future<Size> getWindowSize() async {
    if (!_isDesktop()) return const Size(0, 0);
    return await windowManager.getSize();
  }

  // Initialize window for main app mode
  Future<void> initMainWindow() async {
    if (!_isDesktop()) return;

    try {
      await windowManager.ensureInitialized();

      WindowOptions windowOptions = const WindowOptions(
        size: Size(380, 580),
        minimumSize: Size(380, 340),
        center: true,
        backgroundColor: Color(0xFF1A1A2E),
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        title: 'Work Tracker',
      );

      await windowManager.waitUntilReadyToShow(
        windowOptions,
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );

      _logger.info('Main window initialized');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to initialize main window',
        e,
        stackTrace,
      );
    }
  }

  // Set window size for email entry screen (window IS the card, no extra space)
  Future<void> setAuthWindowSize() async {
    if (!_isDesktop()) return;

    try {
      await windowManager.ensureInitialized();
      await windowManager.setResizable(false);
      await windowManager.setSize(const Size(380, 340));
      await windowManager.center();
      _logger.info('Auth window size set');
    } catch (e, stackTrace) {
      _logger.error('Failed to set auth window size', e, stackTrace);
    }
  }

  // Set window size for OTP verification screen (slightly taller for more content)
  Future<void> setOtpWindowSize() async {
    if (!_isDesktop()) return;

    try {
      await windowManager.ensureInitialized();
      await windowManager.setResizable(false);
      await windowManager.setSize(const Size(380, 520));
      await windowManager.center();
      _logger.info('OTP window size set');
    } catch (e, stackTrace) {
      _logger.error('Failed to set OTP window size', e, stackTrace);
    }
  }

  // Set window size for dashboard (slightly taller for more content)
  Future<void> setDashboardWindowSize() async {
    if (!_isDesktop()) return;

    try {
      await windowManager.ensureInitialized();
      await windowManager.setResizable(false);
      await windowManager.setSize(const Size(380, 580));
      await windowManager.center();
      _logger.info('Dashboard window size set');
    } catch (e, stackTrace) {
      _logger.error('Failed to set dashboard window size', e, stackTrace);
    }
  }

  // Switch to floating widget mode
  Future<void> switchToFloatingMode() async {
    if (!_isDesktop()) return;

    try {
      _isFloatingMode = true;
      _logger.info('Configuring floating mode...');

      // Set window properties
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setMinimumSize(const Size(280, 80));
      await windowManager.setSize(const Size(280, 80));

      // Position window at the RIGHT edge of screen
      try {
        final primaryDisplay = await screenRetriever.getPrimaryDisplay();
        final screenWidth = primaryDisplay.size.width;
        final screenHeight = primaryDisplay.size.height;
        final x = screenWidth - 280;
        final y = (screenHeight - 80) / 2;
        await windowManager.setPosition(Offset(x, y));
      } catch (e) {
        _logger.warning('Could not set window position: $e');
        await windowManager.setPosition(const Offset(1860, 300));
      }

      // Set frameless mode for clean look
      try {
        await windowManager.setBackgroundColor(Colors.transparent);
        await windowManager.setHasShadow(false);
        await windowManager.setAsFrameless();
        await windowManager.setIgnoreMouseEvents(false);

        // On macOS, setAsFrameless() may reduce window height - compensate
        final sizeAfterFrameless = await windowManager.getSize();
        if (sizeAfterFrameless.height < 80) {
          await windowManager.setSize(const Size(280, 80));
        }
      } catch (e) {
        _logger.warning('Could not set frameless mode: $e');
      }

      _logger.info('Window configured for floating mode');
    } catch (e, stackTrace) {
      _logger.error('Failed to configure floating mode', e, stackTrace);
      _isFloatingMode = false;
      rethrow;
    }
  }

  // Switch back to main window mode
  Future<void> switchToMainMode() async {
    if (!_isDesktop()) return;

    try {
      _isFloatingMode = false;
      _logger.info('Configuring main mode...');

      // Restore window settings
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setHasShadow(true);

      // Restore hidden title bar style (keeps window controls visible)
      try {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      } catch (e) {
        _logger.warning('Could not restore title bar: $e');
      }

      // Set window size for dashboard
      await windowManager.setMinimumSize(const Size(380, 580));
      await windowManager.setSize(const Size(380, 580));
      await windowManager.center();

      _logger.info('Window configured for main mode (380x580)');
    } catch (e, stackTrace) {
      _logger.error('Failed to configure main mode', e, stackTrace);
      _isFloatingMode = true;
      rethrow;
    }
  }

  // Toggle between modes
  Future<void> toggleMode() async {
    if (_isFloatingMode) {
      await switchToMainMode();
    } else {
      await switchToFloatingMode();
    }
  }

  // Check if running on desktop
  bool _isDesktop() {
    return Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS;
  }
}
