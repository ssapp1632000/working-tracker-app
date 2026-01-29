import 'dart:io';
import 'package:system_tray/system_tray.dart';
import 'logger_service.dart';

class SystemTrayService {
  static final SystemTrayService _instance = SystemTrayService._internal();
  factory SystemTrayService() => _instance;

  final _logger = LoggerService();
  final SystemTray _systemTray = SystemTray();
  bool _isInitialized = false;

  Function()? onShowWindow;
  Function()? onSwitchToMain;
  Function()? onExit;

  SystemTrayService._internal();

  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (!_isDesktop() || _isInitialized) return;

    try {
      // Get the icon path - need absolute path for Windows
      String iconPath = _getIconPath();
      _logger.info('System tray icon path: $iconPath');

      await _systemTray.initSystemTray(
        title: 'Work Tracker',
        iconPath: iconPath,
        toolTip: 'Work Tracker - Click to show',
      );

      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
          label: 'Show Window',
          onClicked: (menuItem) => onShowWindow?.call(),
        ),
        MenuItemLabel(
          label: 'Open Dashboard',
          onClicked: (menuItem) => onSwitchToMain?.call(),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Exit',
          onClicked: (menuItem) => onExit?.call(),
        ),
      ]);

      await _systemTray.setContextMenu(menu);

      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick ||
            eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
        }
      });

      _isInitialized = true;
      _logger.info('System tray initialized');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize system tray', e, stackTrace);
    }
  }

  Future<void> show() async {
    if (!_isDesktop() || !_isInitialized) return;
    // System tray is always visible once initialized
  }

  Future<void> hide() async {
    if (!_isDesktop() || !_isInitialized) return;
    // We don't hide the tray icon, it stays visible
  }

  Future<void> updateTooltip(String tooltip) async {
    if (!_isDesktop() || !_isInitialized) return;
    try {
      await _systemTray.setToolTip(tooltip);
    } catch (e) {
      _logger.warning('Failed to update tooltip: $e');
    }
  }

  Future<void> destroy() async {
    if (!_isDesktop() || !_isInitialized) return;
    try {
      await _systemTray.destroy();
      _isInitialized = false;
      _logger.info('System tray destroyed');
    } catch (e, stackTrace) {
      _logger.error('Failed to destroy system tray', e, stackTrace);
    }
  }

  bool _isDesktop() {
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  String _getIconPath() {
    // For Windows, we need to use the .ico file from the executable directory
    if (Platform.isWindows) {
      // Get the directory where the executable is located
      final exePath = Platform.resolvedExecutable;
      final exeDir = exePath.substring(0, exePath.lastIndexOf('\\'));
      // The icon should be in data/flutter_assets/ for bundled apps
      // or we use the runner resources for debug mode
      final debugIconPath = '$exeDir\\..\\..\\windows\\runner\\resources\\app_icon.ico';
      final releaseIconPath = '$exeDir\\data\\flutter_assets\\assets\\images\\logo.ico';

      // Check if we're in debug mode (running from IDE)
      if (File(debugIconPath).existsSync()) {
        return debugIconPath;
      } else if (File(releaseIconPath).existsSync()) {
        return releaseIconPath;
      }
      // Fallback - try the windows runner resources with absolute path
      final currentDir = Directory.current.path;
      return '$currentDir\\windows\\runner\\resources\\app_icon.ico';
    }
    // For macOS/Linux, use the PNG from assets
    return 'assets/images/logo.png';
  }
}
