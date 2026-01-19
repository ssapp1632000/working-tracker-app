import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_version_info.dart';
import '../services/update_check_service.dart';
import '../services/logger_service.dart';

// ============================================================================
// UPDATE CHECK STATE
// ============================================================================

sealed class UpdateCheckState {
  const UpdateCheckState();
}

class UpdateCheckInitial extends UpdateCheckState {
  const UpdateCheckInitial();
}

class UpdateCheckLoading extends UpdateCheckState {
  const UpdateCheckLoading();
}

class UpdateCheckAvailable extends UpdateCheckState {
  final AppVersionInfo versionInfo;
  final bool isForceUpdate;

  const UpdateCheckAvailable(this.versionInfo, {this.isForceUpdate = false});
}

class UpdateCheckNotAvailable extends UpdateCheckState {
  const UpdateCheckNotAvailable();
}

class UpdateCheckError extends UpdateCheckState {
  final String message;

  const UpdateCheckError(this.message);
}

class UpdateCheckSkipped extends UpdateCheckState {
  final String skippedVersion;

  const UpdateCheckSkipped(this.skippedVersion);
}

// ============================================================================
// UPDATE CHECK NOTIFIER
// ============================================================================

class UpdateCheckNotifier extends StateNotifier<UpdateCheckState> {
  final _service = UpdateCheckService();
  final _logger = LoggerService();

  UpdateCheckNotifier() : super(const UpdateCheckInitial());

  /// Check for updates from GitHub releases
  Future<void> checkForUpdates({bool force = false}) async {
    try {
      state = const UpdateCheckLoading();

      final versionInfo = await _service.checkForUpdates();

      if (versionInfo == null) {
        state = const UpdateCheckNotAvailable();
        return;
      }

      // Check if update is available
      if (!versionInfo.isUpdateAvailable) {
        _logger.info('App is up to date');
        state = const UpdateCheckNotAvailable();
        return;
      }

      // Check if this version was skipped (unless force update required)
      if (!versionInfo.forceUpdate &&
          !force &&
          _service.isVersionSkipped(versionInfo.latestVersion)) {
        _logger.info('Version ${versionInfo.latestVersion} was skipped by user');
        state = UpdateCheckSkipped(versionInfo.latestVersion);
        return;
      }

      // Update is available
      _logger.info(
        'Update available: ${versionInfo.latestVersion}, '
        'force: ${versionInfo.forceUpdate}',
      );
      state = UpdateCheckAvailable(
        versionInfo,
        isForceUpdate: versionInfo.forceUpdate,
      );
    } catch (e, stackTrace) {
      _logger.error('Error checking for updates', e, stackTrace);
      // Don't show error to user - update check is non-critical
      state = const UpdateCheckNotAvailable();
    }
  }

  /// Skip the current version (user chose "Later")
  Future<void> skipCurrentVersion(String version) async {
    await _service.skipVersion(version);
    state = UpdateCheckSkipped(version);
  }

  /// Open download URL in browser
  Future<bool> openDownload(String url) async {
    return await _service.openDownloadUrl(url);
  }

  /// Reset state to initial
  void reset() {
    state = const UpdateCheckInitial();
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

final updateCheckProvider =
    StateNotifierProvider<UpdateCheckNotifier, UpdateCheckState>((ref) {
  return UpdateCheckNotifier();
});

/// Derived provider for checking if update is available
final isUpdateAvailableProvider = Provider<bool>((ref) {
  final state = ref.watch(updateCheckProvider);
  return state is UpdateCheckAvailable;
});

/// Derived provider for checking if force update is required
final isForceUpdateRequiredProvider = Provider<bool>((ref) {
  final state = ref.watch(updateCheckProvider);
  if (state is UpdateCheckAvailable) {
    return state.isForceUpdate;
  }
  return false;
});
