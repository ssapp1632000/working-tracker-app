import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/window_service.dart';
import '../services/logger_service.dart';

// Window service provider
final windowServiceProvider = Provider<WindowService>((
  ref,
) {
  return WindowService();
});

// Window mode state provider
final windowModeProvider =
    StateNotifierProvider<WindowModeNotifier, bool>((ref) {
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

      // Set state FIRST to hide the dashboard immediately
      // This prevents overflow errors during window resize
      state = true;
      _logger.info('Window mode: Floating (UI updated)');

      // Small delay to let UI update before window resize starts
      await Future.delayed(const Duration(milliseconds: 50));

      // Then configure window to resize
      await _windowService.switchToFloatingMode();

      _logger.info('Window configured for floating mode');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to switch to floating mode',
        e,
        stackTrace,
      );
      state = false;
    }
  }

  // Switch to main mode
  Future<void> switchToMain() async {
    try {
      _logger.info('Switching to main mode...');

      // Resize window FIRST (this hides window during transition)
      // This prevents overflow errors when dashboard renders
      await _windowService.switchToMainMode();

      // THEN update UI state after window is resized
      state = false;
      _logger.info('Window mode: Main (UI updated)');

      _logger.info('Window configured for main mode');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to switch to main mode',
        e,
        stackTrace,
      );
      state = true;
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
