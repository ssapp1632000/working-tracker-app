import 'dart:io';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import 'click_through_service.dart';
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
        minimumSize: Size(380, 580),
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

  // Set window size for dashboard (resizable with minimum constraints)
  Future<void> setDashboardWindowSize() async {
    if (!_isDesktop()) return;

    try {
      await windowManager.ensureInitialized();
      // Set minimum size to current default (380x580)
      await windowManager.setMinimumSize(const Size(380, 580));
      // Remove maximum size constraint to allow free resizing
      await windowManager.setMaximumSize(const Size(1920, 1080));
      await windowManager.setResizable(true);
      await windowManager.setSize(const Size(380, 580));
      await windowManager.center();
      _logger.info('Dashboard window size set (resizable, min: 380x580)');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to set dashboard window size',
        e,
        stackTrace,
      );
    }
  }

  // Switch to floating widget mode
  // Window is always 280px wide, animation handles visual collapse
  static const double _floatingWidth = 280.0;
  static const double _floatingHeight = 80.0;

  Future<void> switchToFloatingMode() async {
    if (!_isDesktop()) return;

    try {
      _isFloatingMode = true;
      _logger.info('Configuring floating mode...');

      // Fade out for smooth transition
      await windowManager.setOpacity(0);

      // Set window properties - always 280px wide
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setMinimumSize(
        const Size(_floatingWidth, _floatingHeight),
      );
      await windowManager.setSize(
        const Size(_floatingWidth, _floatingHeight),
      );

      // Position window at right edge of screen
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

      // Ensure window is visible and can receive mouse events
      await windowManager.show();
      await windowManager.setIgnoreMouseEvents(false);

      // Small delay for window to settle before fading in
      await Future.delayed(const Duration(milliseconds: 50));

      // Fade in
      await windowManager.setOpacity(1);

      // Wait for window to be fully ready before enabling click-through
      await Future.delayed(const Duration(milliseconds: 200));

      // Enable click-through for collapsed state
      await ClickThroughService.setClickThroughEnabled(true);

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
      await windowManager.setOpacity(1);
      rethrow;
    }
  }

  // Switch back to main window mode
  Future<void> switchToMainMode() async {
    if (!_isDesktop()) return;

    try {
      _isFloatingMode = false;
      _logger.info('Configuring main mode...');

      // Disable click-through IMMEDIATELY before any other changes
      // This ensures the window becomes clickable right away
      await ClickThroughService.disableClickThrough();

      // Small delay to ensure native code processes the disable command
      await Future.delayed(const Duration(milliseconds: 50));

      // Fade out for smooth transition
      await windowManager.setOpacity(0);

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

      // Set window size for dashboard with free resizing (min: 380x580)
      await windowManager.setMinimumSize(
        const Size(380, 580),
      );
      await windowManager.setMaximumSize(
        const Size(1920, 1080),
      );
      await windowManager.setResizable(true);
      await windowManager.setSize(const Size(380, 580));
      await windowManager.center();

      // Ensure window is visible
      await windowManager.show();
      await windowManager.focus();

      // Small delay for window to settle before fading in
      await Future.delayed(const Duration(milliseconds: 50));

      // Fade in
      await windowManager.setOpacity(1);

      // Ensure click-through is disabled one more time after all window changes
      // This is a safety measure to prevent any edge cases
      await ClickThroughService.disableClickThrough();

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
      await windowManager.setOpacity(1);
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
