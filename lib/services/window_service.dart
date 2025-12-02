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
      _logger.error(
        'Failed to set auth window size',
        e,
        stackTrace,
      );
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
      _logger.error(
        'Failed to set OTP window size',
        e,
        stackTrace,
      );
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
      _logger.error(
        'Failed to set dashboard window size',
        e,
        stackTrace,
      );
    }
  }

  // Switch to floating widget mode
  // Window is always 280px wide, positioned at right edge of screen
  static const double _floatingWidth = 280.0;
  static const double _floatingHeight = 80.0;

  Future<void> switchToFloatingMode() async {
    if (!_isDesktop()) return;

    try {
      _isFloatingMode = true;
      _logger.info('Configuring floating mode...');

      // Hide window during transition to prevent visual jump
      await windowManager.hide();

      // Set window properties - always 280px wide
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setMinimumSize(
        const Size(_floatingWidth, _floatingHeight),
      );
      await windowManager.setSize(
        const Size(_floatingWidth, _floatingHeight),
      );

      // Position window at right edge of screen (fully visible)
      try {
        final primaryDisplay = await screenRetriever
            .getPrimaryDisplay();
        final screenWidth = primaryDisplay.size.width;
        final screenHeight = primaryDisplay.size.height;
        // Position so right edge aligns with screen edge
        final x = screenWidth - _floatingWidth;
        final y = (screenHeight - _floatingHeight) / 2;
        await windowManager.setPosition(Offset(x, y));
      } catch (e) {
        _logger.warning(
          'Could not set window position: $e',
        );
        await windowManager.setPosition(
          const Offset(1640, 300),
        );
      }

      // Set frameless mode for clean look
      try {
        await windowManager.setBackgroundColor(
          Colors.transparent,
        );
        await windowManager.setHasShadow(false);
        await windowManager.setAsFrameless();
        await windowManager.setIgnoreMouseEvents(false);

        // On macOS, setAsFrameless() may reduce window height - compensate
        final sizeAfterFrameless = await windowManager
            .getSize();
        if (sizeAfterFrameless.height < _floatingHeight) {
          await windowManager.setSize(
            Size(_floatingWidth, _floatingHeight),
          );
        }
      } catch (e) {
        _logger.warning('Could not set frameless mode: $e');
      }

      // Show window after repositioning is complete
      await windowManager.show();

      _logger.info('Window configured for floating mode');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to configure floating mode',
        e,
        stackTrace,
      );
      _isFloatingMode = false;
      // Make sure window is visible even on error
      await windowManager.show();
      rethrow;
    }
  }

  // Switch back to main window mode
  Future<void> switchToMainMode() async {
    if (!_isDesktop()) return;

    try {
      _isFloatingMode = false;
      _logger.info('Configuring main mode...');

      // Hide window during transition to prevent visual jump
      await windowManager.hide();

      // Restore window settings
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setHasShadow(true);

      // Restore hidden title bar style (keeps window controls visible)
      try {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
        );
      } catch (e) {
        _logger.warning('Could not restore title bar: $e');
      }

      // Set window size for dashboard
      await windowManager.setMinimumSize(
        const Size(380, 580),
      );
      await windowManager.setSize(const Size(380, 580));
      await windowManager.center();

      // Show window after repositioning is complete
      await windowManager.show();
      await windowManager.focus();

      _logger.info(
        'Window configured for main mode (380x580)',
      );
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to configure main mode',
        e,
        stackTrace,
      );
      _isFloatingMode = true;
      // Make sure window is visible even on error
      await windowManager.show();
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
