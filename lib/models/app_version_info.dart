import '../core/constants/app_constants.dart';

/// Model for app version information from GitHub releases
class AppVersionInfo {
  final String latestVersion;
  final String? minimumVersion;
  final String downloadUrl;
  final String? releaseNotes;
  final String? releaseName;
  final DateTime? releaseDate;

  AppVersionInfo({
    required this.latestVersion,
    this.minimumVersion,
    required this.downloadUrl,
    this.releaseNotes,
    this.releaseName,
    this.releaseDate,
  });

  /// Check if an update is available by comparing versions
  bool get isUpdateAvailable {
    return _compareVersions(latestVersion, AppConstants.appVersion) > 0;
  }

  /// Check if this is a force update (current version below minimum)
  bool get forceUpdate {
    if (minimumVersion == null) return false;
    return _compareVersions(minimumVersion!, AppConstants.appVersion) > 0;
  }

  /// Compare two semantic versions
  /// Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
  static int _compareVersions(String v1, String v2) {
    // Remove 'v' prefix if present
    v1 = v1.replaceFirst(RegExp(r'^v'), '');
    v2 = v2.replaceFirst(RegExp(r'^v'), '');

    final parts1 = v1.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final parts2 = v2.split('.').map((p) => int.tryParse(p) ?? 0).toList();

    // Pad shorter version with zeros
    while (parts1.length < 3) {
      parts1.add(0);
    }
    while (parts2.length < 3) {
      parts2.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (parts1[i] > parts2[i]) return 1;
      if (parts1[i] < parts2[i]) return -1;
    }
    return 0;
  }

  /// Create from GitHub releases API response
  factory AppVersionInfo.fromGitHubRelease(Map<String, dynamic> json) {
    final tagName = json['tag_name'] as String? ?? '';
    final body = json['body'] as String? ?? '';
    final htmlUrl = json['html_url'] as String? ?? '';
    final name = json['name'] as String?;
    final publishedAt = json['published_at'] as String?;

    // Try to get download URL from assets, fallback to release page
    String downloadUrl = htmlUrl;
    final assets = json['assets'] as List<dynamic>?;
    if (assets != null && assets.isNotEmpty) {
      // Look for Windows executable
      for (final asset in assets) {
        final assetName = (asset['name'] as String? ?? '').toLowerCase();
        if (assetName.endsWith('.exe') || assetName.contains('windows')) {
          downloadUrl = asset['browser_download_url'] as String? ?? htmlUrl;
          break;
        }
      }
      // If no Windows-specific asset found, use first asset or release page
      if (downloadUrl == htmlUrl && assets.isNotEmpty) {
        downloadUrl = assets.first['browser_download_url'] as String? ?? htmlUrl;
      }
    }

    // Parse minimum version from release notes if present
    // Format: <!-- UPDATE_CONFIG {"minimumVersion": "1.0.5"} -->
    String? minimumVersion;
    final configMatch = RegExp(r'<!--\s*UPDATE_CONFIG\s*(\{[^}]+\})\s*-->').firstMatch(body);
    if (configMatch != null) {
      try {
        final configStr = configMatch.group(1);
        if (configStr != null) {
          // Simple JSON parsing for minimumVersion
          final minVersionMatch = RegExp(r'"minimumVersion"\s*:\s*"([^"]+)"').firstMatch(configStr);
          if (minVersionMatch != null) {
            minimumVersion = minVersionMatch.group(1);
          }
        }
      } catch (_) {
        // Ignore parsing errors
      }
    }

    return AppVersionInfo(
      latestVersion: tagName.replaceFirst(RegExp(r'^v'), ''),
      minimumVersion: minimumVersion,
      downloadUrl: downloadUrl,
      releaseNotes: body.isNotEmpty ? _cleanReleaseNotes(body) : null,
      releaseName: name,
      releaseDate: publishedAt != null ? DateTime.tryParse(publishedAt) : null,
    );
  }

  /// Remove config comments from release notes for display
  static String _cleanReleaseNotes(String notes) {
    return notes
        .replaceAll(RegExp(r'<!--\s*UPDATE_CONFIG\s*\{[^}]+\}\s*-->'), '')
        .trim();
  }

  @override
  String toString() {
    return 'AppVersionInfo(latestVersion: $latestVersion, minimumVersion: $minimumVersion, '
        'isUpdateAvailable: $isUpdateAvailable, forceUpdate: $forceUpdate)';
  }
}
