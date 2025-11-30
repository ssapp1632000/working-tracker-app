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
        size: Size(800, 600),
        minimumSize: Size(600, 400),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
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

  // Switch to floating widget mode
  Future<void> switchToFloatingMode() async {
    if (!_isDesktop()) return;

    try {
      _isFloatingMode = true;
      _logger.info('Configuring floating mode...');

      // First, set always on top and skip taskbar BEFORE changing size
      _logger.info('Setting window properties...');
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);

      // Small delay to let properties settle
      await Future.delayed(
        const Duration(milliseconds: 150),
      );

      // Set minimum size to 280x80
      _logger.info('Setting minimum size...');
      await windowManager.setMinimumSize(
        const Size(280, 80),
      );

      // Another small delay
      await Future.delayed(
        const Duration(milliseconds: 100),
      );

      // Window size 280x80
      _logger.info(
        'Resizing window to 280x80...',
      );
      await windowManager.setSize(const Size(280, 80));

      // Wait for window manager to actually apply the size
      await Future.delayed(
        const Duration(milliseconds: 100),
      );

      // Verify the size was set correctly
      final currentSize = await windowManager.getSize();
      _logger.info(
        'Window size after setSize: ${currentSize.width}x${currentSize.height}',
      );

      // If size is incorrect, try multiple times to ensure it sticks
      if (currentSize.height < 80) {
        _logger.warning(
          'Window height is ${currentSize.height}, expected 80. Retrying...',
        );

        // Try setting it 2 more times with increasing delays
        for (int i = 0; i < 2; i++) {
          await windowManager.setSize(const Size(280, 80));
          await Future.delayed(
            const Duration(milliseconds: 150),
          );

          final checkSize = await windowManager.getSize();
          _logger.info(
            'Retry ${i + 1} - Window size: ${checkSize.width}x${checkSize.height}',
          );

          if (checkSize.height >= 80) {
            _logger.info(
              'Window size correction successful',
            );
            break;
          }
        }

        final finalSize = await windowManager.getSize();
        _logger.info(
          'Final window size: ${finalSize.width}x${finalSize.height}',
        );
      }

      // Position window at the RIGHT edge of screen
      try {
        _logger.info('Positioning window...');

        // Get primary display to calculate right edge position
        final primaryDisplay = await screenRetriever
            .getPrimaryDisplay();
        final screenWidth = primaryDisplay.size.width;
        final screenHeight = primaryDisplay.size.height;

        // Position window at right edge, vertically centered
        final currentSize = await windowManager.getSize();
        final x = screenWidth - currentSize.width;
        final y = (screenHeight - currentSize.height) / 2;

        _logger.info(
          'Positioning ${currentSize.width}px window at ($x, $y) - right edge of ${screenWidth}px screen',
        );
        await windowManager.setPosition(Offset(x, y));
      } catch (e) {
        _logger.warning(
          'Could not set window position: $e',
        );
        // Fallback to fixed position if positioning fails
        await windowManager.setPosition(
          const Offset(1860, 300),
        );
      }

      // Set frameless mode for clean look
      try {
        _logger.info('Setting frameless mode...');

        // Set background to transparent BEFORE frameless mode
        await windowManager.setBackgroundColor(
          Colors.transparent,
        );
        _logger.info(
          'Set window background to transparent',
        );

        // Disable window shadow for better transparency on macOS
        await windowManager.setHasShadow(false);
        _logger.info(
          'Disabled window shadow for transparency',
        );

        await windowManager.setAsFrameless();

        // IMPORTANT: Ensure window can receive mouse events
        // Without this, clicking might cause crashes in frameless mode
        await windowManager.setIgnoreMouseEvents(false);

        _logger.info(
          'Frameless mode configured with mouse events enabled',
        );

        // CRITICAL: On macOS, setAsFrameless() removes the title bar which reduces
        // the window height. We need to compensate by resizing after frameless is set.
        await Future.delayed(
          const Duration(milliseconds: 50),
        );

        final sizeAfterFrameless = await windowManager
            .getSize();
        _logger.info(
          'Size after frameless: ${sizeAfterFrameless.width}x${sizeAfterFrameless.height}',
        );

        if (sizeAfterFrameless.height < 80) {
          _logger.info(
            'Compensating for frameless height loss...',
          );
          await windowManager.setSize(const Size(280, 80));
          await Future.delayed(
            const Duration(milliseconds: 100),
          );

          final compensatedSize = await windowManager
              .getSize();
          _logger.info(
            'Size after compensation: ${compensatedSize.width}x${compensatedSize.height}',
          );
        }
      } catch (e) {
        _logger.warning('Could not set frameless mode: $e');
      }

      _logger.info(
        'Window configured for floating mode successfully',
      );

      // Final verification and correction after all operations
      await Future.delayed(
        const Duration(milliseconds: 100),
      );
      final verifySize = await windowManager.getSize();
      _logger.info(
        'Final verification - Window size: ${verifySize.width}x${verifySize.height}',
      );

      if (verifySize.height < 80) {
        _logger.warning(
          'Final size check failed, forcing size one more time',
        );
        await windowManager.setSize(const Size(280, 80));
        await Future.delayed(
          const Duration(milliseconds: 150),
        );
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to configure floating mode',
        e,
        stackTrace,
      );
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

      // Restore minimum size
      await windowManager.setMinimumSize(
        const Size(600, 400),
      );

      // Small delay to let UI update
      await Future.delayed(
        const Duration(milliseconds: 100),
      );

      // Restore window frame (remove frameless mode)
      try {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.normal,
        );
      } catch (e) {
        _logger.warning('Could not restore title bar: $e');
      }

      // Restore window settings
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setSize(const Size(800, 600));
      await windowManager.center();

      _logger.info('Window configured for main mode');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to configure main mode',
        e,
        stackTrace,
      );
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
