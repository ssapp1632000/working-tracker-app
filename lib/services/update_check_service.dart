import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../models/app_version_info.dart';
import 'logger_service.dart';
import 'storage_service.dart';

/// Service for checking app updates from GitHub releases
class UpdateCheckService {
  static final UpdateCheckService _instance = UpdateCheckService._internal();
  factory UpdateCheckService() => _instance;

  final _logger = LoggerService();
  final _storage = StorageService();

  UpdateCheckService._internal();

  /// Get GitHub repo from .env (format: "owner/repo")
  String? get _githubRepo => dotenv.env['GITHUB_REPO'];

  /// Check for updates from GitHub releases
  /// Returns AppVersionInfo if successful, null otherwise
  Future<AppVersionInfo?> checkForUpdates() async {
    try {
      final repo = _githubRepo;
      if (repo == null || repo.isEmpty || !repo.contains('/')) {
        _logger.warning('GITHUB_REPO not configured in .env file');
        return null;
      }

      final url = 'https://api.github.com/repos/$repo/releases/latest';
      _logger.info('Checking for updates from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'SilverStone-Desktop-App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final versionInfo = AppVersionInfo.fromGitHubRelease(data);
        _logger.info('Latest version: ${versionInfo.latestVersion}, '
            'Update available: ${versionInfo.isUpdateAvailable}');
        return versionInfo;
      } else if (response.statusCode == 404) {
        _logger.info('No releases found for repository');
        return null;
      } else {
        _logger.warning('Failed to check for updates: ${response.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      _logger.error('Error checking for updates', e, stackTrace);
      return null;
    }
  }

  /// Open download URL in default browser
  Future<bool> openDownloadUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        _logger.info('Opened download URL: $url');
        return true;
      } else {
        _logger.warning('Cannot launch URL: $url');
        return false;
      }
    } catch (e, stackTrace) {
      _logger.error('Error opening download URL', e, stackTrace);
      return false;
    }
  }

  /// Check if user has skipped this version
  bool isVersionSkipped(String version) {
    final skipped = _storage.getSkippedVersion();
    return skipped == version;
  }

  /// Mark a version as skipped (user chose "Later")
  Future<void> skipVersion(String version) async {
    await _storage.setSkippedVersion(version);
    _logger.info('Skipped version: $version');
  }

  /// Clear the skipped version preference
  Future<void> clearSkippedVersion() async {
    await _storage.clearSkippedVersion();
    _logger.info('Cleared skipped version');
  }
}
