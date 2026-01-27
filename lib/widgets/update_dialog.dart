import 'dart:io' show exit;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:auto_updater/auto_updater.dart';
import '../core/theme/app_theme.dart';
import '../services/app_info_service.dart';
import '../services/auto_update_service.dart';

/// Mandatory update dialog - users MUST update to continue using the app
class UpdateDialog extends ConsumerStatefulWidget {
  final AppcastItem updateInfo;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
  });

  /// Show the mandatory update dialog (cannot be dismissed)
  static Future<void> show({
    required BuildContext context,
    required AppcastItem updateInfo,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false, // Cannot dismiss by tapping outside
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => UpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  bool _isDownloading = false;
  bool _isReadyToInstall = false;
  String? _errorMessage;
  final _autoUpdateService = AutoUpdateService();

  @override
  void initState() {
    super.initState();
    _setupUpdateCallbacks();
  }

  void _setupUpdateCallbacks() {
    _autoUpdateService.onUpdateDownloaded = (item) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isReadyToInstall = true;
        });
      }
    };

    _autoUpdateService.onError = (error) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = error;
        });
      }
    };
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
    });

    // Trigger the update check which will download the update
    await _autoUpdateService.checkForUpdates();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Cannot use back button/escape to close
      child: Dialog(
        backgroundColor: AppTheme.surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Update icon
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.elevatedSurfaceColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _isReadyToInstall
                        ? Icons.check_circle_rounded
                        : Icons.system_update_rounded,
                    color: _isReadyToInstall
                        ? AppTheme.successColor
                        : AppTheme.secondaryColor,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  _isReadyToInstall ? 'Update Ready' : 'Update Required',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),

                // Version info
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                    children: [
                      const TextSpan(text: 'Version '),
                      TextSpan(
                        text: widget.updateInfo.versionString ?? 'New',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' is available\n'),
                      TextSpan(
                        text: 'Current: ${AppInfoService().version}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Mandatory update notice
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.secondaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: AppTheme.secondaryColor,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _isReadyToInstall
                              ? 'Click below to install the update'
                              : 'Please update to continue using the app',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.secondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Error message
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: AppTheme.errorColor,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.errorColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Download progress or button
                if (_isDownloading) ...[
                  const SizedBox(height: 8),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    'Downloading update...',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ] else if (_isReadyToInstall) ...[
                  // Install button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Quit app and install update
                        // The installer will restart the app after installation
                        exit(0);
                      },
                      icon: const Icon(Icons.install_desktop_rounded, size: 20),
                      label: const Text(
                        'Install & Restart',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.successColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // Update Now button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _startDownload,
                      icon: const Icon(Icons.download_rounded, size: 20),
                      label: const Text(
                        'Update Now',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.secondaryColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],

                // No "Later" button - update is mandatory
              ],
            ),
          ),
        ),
      ),
    );
  }
}
