import 'dart:io';
import 'package:flutter/services.dart';

/// Service to control click-through behavior on Windows
/// Uses WS_EX_TRANSPARENT window style to toggle click-through
class ClickThroughService {
  static const MethodChannel _channel = MethodChannel(
    'com.worktracker/click_through',
  );

  /// Enable or disable click-through mode for the entire window
  /// When enabled, the window is transparent to mouse events
  /// When disabled, the window receives mouse events normally
  static Future<void> setClickThroughEnabled(bool enabled) async {
    if (!Platform.isWindows) return;

    try {
      await _channel.invokeMethod('setClickThroughEnabled', enabled);
    } catch (e) {
      // Silently ignore errors
    }
  }

  /// Disable click-through (make window clickable)
  static Future<void> disableClickThrough() async {
    await setClickThroughEnabled(false);
  }

  /// Enable click-through (make window transparent to clicks)
  static Future<void> enableClickThrough() async {
    await setClickThroughEnabled(true);
  }

  /// Restore normal window style (WS_OVERLAPPEDWINDOW)
  /// This restores resize borders (WS_THICKFRAME) and removes layered styles
  /// Call this when switching back from floating mode to ensure proper window behavior
  static Future<void> restoreNormalWindowStyle() async {
    if (!Platform.isWindows) return;

    try {
      await _channel.invokeMethod('restoreNormalWindowStyle');
    } catch (e) {
      // Silently ignore errors
    }
  }

  /// Set frameless mode for the window
  /// When enabled, removes all window frame styles (caption, borders, etc.)
  /// When disabled, restores window frame styles
  static Future<void> setFrameless(bool frameless) async {
    if (!Platform.isWindows) return;

    try {
      await _channel.invokeMethod('setFrameless', frameless);
    } catch (e) {
      // Silently ignore errors
    }
  }
}
