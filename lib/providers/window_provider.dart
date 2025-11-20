import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/window_service.dart';
import '../services/logger_service.dart';

// Window service provider
final windowServiceProvider = Provider<WindowService>((ref) {
  return WindowService();
});

// Window mode state provider
final windowModeProvider = StateNotifierProvider<WindowModeNotifier, bool>((ref) {
  return WindowModeNotifier(ref);
});

class WindowModeNotifier extends StateNotifier<bool> {
  final Ref _ref;
  late final WindowService _windowService;
  late final LoggerService _logger;

  // State: true = floating mode, false = main mode
  WindowModeNotifier(this._ref) : super(false) {
    _windowService = _ref.read(windowServiceProvider);
    _logger = LoggerService();
  }

  // Switch to floating mode
  Future<void> switchToFloating() async {
    try {
      _logger.info('Switching to floating mode...');

      // Configure window FIRST before changing UI state
      // This ensures proper window size before Flutter renders
      await _windowService.switchToFloatingMode();

      // Poll the actual window size until it matches what we requested (60x80)
      // This ensures the window has ACTUALLY resized before we trigger UI changes
      bool sizeCorrect = false;
      int attempts = 0;
      const maxAttempts = 10; // Try for up to 500ms (10 * 50ms)

      while (!sizeCorrect && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 50));
        final verifySize = await _windowService.getWindowSize();

        _logger.info('Attempt ${attempts + 1} - Window size: ${verifySize.width}x${verifySize.height}');

        // Check if size is correct (60x80 collapsed state)
        if (verifySize.width <= 80 && verifySize.height >= 60) {
          sizeCorrect = true;
          _logger.info('Window size verified (${verifySize.width}x${verifySize.height}) - proceeding with UI update');
        } else {
          attempts++;
          if (attempts >= maxAttempts) {
            _logger.warning('Window did not resize to expected size after $maxAttempts attempts');
            _logger.warning('Expected: ~60x80, Got: ${verifySize.width}x${verifySize.height}');
          }
        }
      }

      // Then set state to trigger UI change
      state = true;
      _logger.info('Window mode: Floating');
    } catch (e, stackTrace) {
      _logger.error('Failed to switch to floating mode', e, stackTrace);
      state = false; // Revert on error
    }
  }

  // Switch to main mode
  Future<void> switchToMain() async {
    try {
      _logger.info('Switching to main mode...');

      // Configure window FIRST to resize before UI change
      // This prevents overflow when dashboard tries to render in 60x80 window
      await _windowService.switchToMainMode();

      // Poll the actual window size until it matches what we requested (800x600)
      // This ensures the window has ACTUALLY resized before we trigger UI changes
      bool sizeCorrect = false;
      int attempts = 0;
      const maxAttempts = 10; // Try for up to 500ms (10 * 50ms)

      while (!sizeCorrect && attempts < maxAttempts) {
        await Future.delayed(const Duration(milliseconds: 50));
        final verifySize = await _windowService.getWindowSize();

        _logger.info('Attempt ${attempts + 1} - Window size: ${verifySize.width}x${verifySize.height}');

        // Check if size is correct (at least 600x400, should be 800x600)
        if (verifySize.width >= 600 && verifySize.height >= 400) {
          sizeCorrect = true;
          _logger.info('Window size verified (${verifySize.width}x${verifySize.height}) - proceeding with UI update');
        } else {
          attempts++;
          if (attempts >= maxAttempts) {
            _logger.warning('Window did not resize to expected size after $maxAttempts attempts');
            _logger.warning('Expected: at least 600x400, Got: ${verifySize.width}x${verifySize.height}');
          }
        }
      }

      // Then set state to trigger UI change to dashboard
      state = false;
      _logger.info('Window mode: Main');
    } catch (e, stackTrace) {
      _logger.error('Failed to switch to main mode', e, stackTrace);
      state = true; // Revert on error
    }
  }

  // Toggle between modes
  Future<void> toggle() async {
    if (state) {
      await switchToMain();
    } else {
      await switchToFloating();
    }
  }

  // Check current mode
  bool get isFloating => state;
}
