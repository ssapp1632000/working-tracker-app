import 'dart:io';
import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'logger_service.dart';
import 'app_info_service.dart';

/// Service for handling automatic app updates via auto_updater
class AutoUpdateService with UpdaterListener {
  static final AutoUpdateService _instance = AutoUpdateService._internal();
  factory AutoUpdateService() => _instance;

  final _logger = LoggerService();
  final _appInfo = AppInfoService();

  bool _isInitialized = false;
  bool _updateAvailable = false;
  bool _updateDownloaded = false;
  AppcastItem? _latestUpdate;
  String? _errorMessage;

  // Callbacks for UI updates
  Function(AppcastItem item)? onUpdateAvailable;
  Function(AppcastItem item)? onUpdateDownloaded;
  Function(AppcastItem item)? onBeforeQuitForUpdate;
  Function(String error)? onError;

  AutoUpdateService._internal();

  /// Get the AppCast feed URL from environment or use default
  String get feedUrl {
    final githubRepo =
        dotenv.env['GITHUB_REPO'] ?? 'ssapp1632000/working-tracker-app';
    final parts = githubRepo.split('/');
    if (parts.length != 2) {
      return 'https://ssapp1632000.github.io/working-tracker-app/appcast.xml';
    }
    // AppCast hosted on GitHub Pages
    return 'https://${parts[0]}.github.io/${parts[1]}/appcast.xml';
  }

  bool get isInitialized => _isInitialized;
  bool get updateAvailable => _updateAvailable;
  bool get updateDownloaded => _updateDownloaded;
  AppcastItem? get latestUpdate => _latestUpdate;
  String? get errorMessage => _errorMessage;

  /// Initialize the auto-updater (call on app start)
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Only run on desktop platforms
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      _logger.info('Auto-updater not supported on this platform');
      return;
    }

    try {
      _logger.info('Initializing auto-updater with feed: $feedUrl');

      // Add this service as a listener
      autoUpdater.addListener(this);

      // Set the feed URL
      await autoUpdater.setFeedURL(feedUrl);

      _isInitialized = true;
      _logger.info('Auto-updater initialized successfully');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize auto-updater', e, stackTrace);
      _errorMessage = e.toString();
    }
  }

  /// Check for updates
  Future<void> checkForUpdates({bool inBackground = false}) async {
    if (!_isInitialized) {
      _logger.warning('Auto-updater not initialized, cannot check for updates');
      return;
    }

    try {
      _logger.info('Checking for updates (background: $inBackground)...');
      _errorMessage = null;
      await autoUpdater.checkForUpdates(inBackground: inBackground);
    } catch (e, stackTrace) {
      _logger.error('Error checking for updates', e, stackTrace);
      _errorMessage = e.toString();
      onError?.call(e.toString());
    }
  }

  /// Set auto-check interval (in seconds)
  /// Default: 86400 (24 hours), Minimum: 3600 (1 hour), 0 to disable
  Future<void> setCheckInterval(int seconds) async {
    if (!_isInitialized) return;
    await autoUpdater.setScheduledCheckInterval(seconds);
    _logger.info('Auto-update check interval set to $seconds seconds');
  }

  // UpdaterListener implementation

  @override
  void onUpdaterError(UpdaterError? error) {
    final errorMsg = error?.toString() ?? 'Unknown error';
    _logger.error('Auto-updater error: $errorMsg');
    _errorMessage = errorMsg;
    onError?.call(errorMsg);
  }

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    _logger.info(
        'Checking for update... Found ${appcast?.items.length ?? 0} items');
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? appcastItem) {
    if (appcastItem == null) return;

    _logger.info('Update available: ${appcastItem.versionString}');
    _updateAvailable = true;
    _latestUpdate = appcastItem;
    onUpdateAvailable?.call(appcastItem);
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _logger.info('No update available. Current version: ${_appInfo.version}');
    _updateAvailable = false;
    _latestUpdate = null;
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? appcastItem) {
    if (appcastItem == null) return;

    _logger.info('Update downloaded: ${appcastItem.versionString}');
    _updateDownloaded = true;
    _latestUpdate = appcastItem;
    onUpdateDownloaded?.call(appcastItem);
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? appcastItem) {
    if (appcastItem == null) return;

    _logger.info('About to quit and install: ${appcastItem.versionString}');
    onBeforeQuitForUpdate?.call(appcastItem);
  }

  /// Clean up resources
  void dispose() {
    autoUpdater.removeListener(this);
    onUpdateAvailable = null;
    onUpdateDownloaded = null;
    onBeforeQuitForUpdate = null;
    onError = null;
  }
}
