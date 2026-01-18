import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/window_service.dart';
import '../services/logger_service.dart';

// Window service provider
final windowServiceProvider = Provider<WindowService>((ref) {
  return WindowService();
});

/// Provider to track if in floating mode
final floatingWindowOpenProvider = StateProvider<bool>((ref) => false);

/// Window mode notifier for managing window state
///
/// Single-window architecture with two modes:
/// - Main mode: Normal resizable window with standard frame
/// - Floating mode: Small always-on-top window with hidden title bar
class WindowModeNotifier extends StateNotifier<bool> {
  final Ref _ref;
  late final WindowService _windowService;
  late final LoggerService _logger;

  // State: true = floating mode, false = main mode
  WindowModeNotifier(this._ref) : super(false) {
    _windowService = _ref.read(windowServiceProvider);
    _logger = LoggerService();
  }

  /// Switch to floating mode
  Future<void> switchToFloating() async {
    try {
      _logger.info('Switching to floating mode...');

      // Set state BEFORE changing window size to prevent dashboard
      // from rendering with tiny window during transition
      state = true;
      _ref.read(floatingWindowOpenProvider.notifier).state = true;

      await _windowService.switchToFloatingMode();

      _logger.info('Switched to floating mode');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to switch to floating mode',
        e,
        stackTrace,
      );
      state = false;
      _ref.read(floatingWindowOpenProvider.notifier).state = false;
    }
  }

  /// Switch back to main mode
  Future<void> switchToMain() async {
    try {
      _logger.info('Switching to main mode...');

      // First restore window size, then update state
      // This prevents FloatingWidget from rendering with large window during transition
      await _windowService.switchToMainMode();

      state = false;
      _ref.read(floatingWindowOpenProvider.notifier).state = false;

      _logger.info('Switched to main mode');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to switch to main mode',
        e,
        stackTrace,
      );
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

// Window mode state provider
final windowModeProvider = StateNotifierProvider<WindowModeNotifier, bool>((ref) {
  return WindowModeNotifier(ref);
});
