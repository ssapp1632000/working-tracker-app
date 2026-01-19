import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_version_info.dart';
import '../providers/update_check_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/constants/app_constants.dart';

/// Dialog shown when an app update is available
class UpdateDialog extends ConsumerWidget {
  final AppVersionInfo versionInfo;
  final bool isForceUpdate;

  const UpdateDialog({
    super.key,
    required this.versionInfo,
    this.isForceUpdate = false,
  });

  /// Show the update dialog
  static Future<void> show({
    required BuildContext context,
    required AppVersionInfo versionInfo,
    bool isForceUpdate = false,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: !isForceUpdate,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => UpdateDialog(
        versionInfo: versionInfo,
        isForceUpdate: isForceUpdate,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: !isForceUpdate,
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
                    isForceUpdate
                        ? Icons.security_update_warning_rounded
                        : Icons.system_update_rounded,
                    color: isForceUpdate
                        ? AppTheme.warningColor
                        : AppTheme.successColor,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  isForceUpdate ? 'Update Required' : 'Update Available',
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
                        text: versionInfo.latestVersion,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const TextSpan(text: ' is available\n'),
                      TextSpan(
                        text: 'Current: ${AppConstants.appVersion}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Release notes (if available)
                if (versionInfo.releaseNotes != null &&
                    versionInfo.releaseNotes!.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.elevatedSurfaceColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Text(
                        versionInfo.releaseNotes!,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Force update warning
                if (isForceUpdate) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppTheme.errorColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: AppTheme.errorColor,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'This update is required to continue using the app',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.errorColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                const SizedBox(height: 8),

                // Update Now button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final success = await ref
                          .read(updateCheckProvider.notifier)
                          .openDownload(versionInfo.downloadUrl);

                      if (!success && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Could not open download page'),
                            backgroundColor: AppTheme.errorColor,
                          ),
                        );
                      }

                      // Don't close dialog for force updates
                      if (!isForceUpdate && context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.download_rounded, size: 20),
                    label: const Text(
                      'Update Now',
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

                // Later button (only for non-force updates)
                if (!isForceUpdate) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        ref
                            .read(updateCheckProvider.notifier)
                            .skipCurrentVersion(versionInfo.latestVersion);
                        Navigator.of(context).pop();
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: AppTheme.textSecondary.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Later',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
