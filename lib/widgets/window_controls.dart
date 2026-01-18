import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/app_theme.dart';

/// Custom window control buttons (minimize, fullscreen, close)
/// for Windows desktop app with hidden title bar.
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _checkFullScreenState();
  }

  Future<void> _checkFullScreenState() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Check both fullscreen and maximized states
      final isFullScreen = await windowManager.isFullScreen();
      final isMaximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isFullScreen = isFullScreen || isMaximized);
      }
    }
  }

  Future<void> _toggleFullScreen() async {
    final newState = !_isFullScreen;

    if (newState) {
      // Remove size constraints to allow maximize
      await windowManager.setMinimumSize(const Size(0, 0));
      await windowManager.setMaximumSize(const Size(9999, 9999));
      await windowManager.setResizable(true);
      await Future.delayed(const Duration(milliseconds: 100));
      // Use maximize instead of setFullScreen for better taskbar compatibility
      await windowManager.maximize();
    } else {
      // Exit maximized state
      await windowManager.unmaximize();
      await Future.delayed(const Duration(milliseconds: 150));
      // Restore original size constraints and position
      await windowManager.setMinimumSize(const Size(420, 800));
      await windowManager.setMaximumSize(const Size(420, 800));
      await windowManager.setResizable(false);
      await windowManager.setSize(const Size(420, 800));
      await Future.delayed(const Duration(milliseconds: 50));
      await windowManager.center();
    }

    // Wait for window state to settle
    await Future.delayed(const Duration(milliseconds: 100));

    // Check actual state (check maximized instead of fullscreen)
    final isMaximized = await windowManager.isMaximized();

    if (mounted) {
      setState(() => _isFullScreen = isMaximized);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show on desktop platforms
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      // Allow dragging the window from this area
      onPanStart: (_) => windowManager.startDragging(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowButton(
            icon: Icons.remove,
            onPressed: () => windowManager.minimize(),
            tooltip: 'Minimize',
          ),
          _WindowButton(
            icon: _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
            onPressed: _toggleFullScreen,
            tooltip: _isFullScreen ? 'Exit Full Screen' : 'Full Screen',
          ),
          _WindowButton(
            icon: Icons.close,
            onPressed: () => windowManager.close(),
            tooltip: 'Close',
            isClose: true,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.isClose
                      ? Colors.red.withValues(alpha: 0.8)
                      : Colors.white.withValues(alpha: 0.2))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              widget.icon,
              size: 16,
              color: _isHovered && widget.isClose
                  ? Colors.white
                  : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
