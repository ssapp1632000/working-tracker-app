import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'logger_service.dart';

/// Native audio recorder for macOS and Windows
/// Uses AVFoundation on macOS and Media Foundation on Windows
class NativeAudioRecorder {
  static const _channel = MethodChannel('com.silverstone.audio_recorder');
  final _logger = LoggerService();

  String? _currentPath;
  bool _isRecording = false;

  bool get isRecording => _isRecording;
  String? get currentPath => _currentPath;

  /// Check if the current platform is supported
  bool get isSupported => Platform.isMacOS || Platform.isWindows;

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    if (!isSupported) {
      _logger.warning('Native recorder not supported on this platform');
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('hasPermission');
      return result ?? false;
    } catch (e) {
      _logger.error('Error checking permission', e, null);
      return false;
    }
  }

  /// Start recording to a file
  Future<bool> startRecording() async {
    if (_isRecording) {
      _logger.warning('Already recording');
      return false;
    }

    if (!isSupported) {
      _logger.warning('Native recorder not supported on this platform');
      return false;
    }

    try {
      // Generate file path - use .m4a for both platforms (AAC container)
      final tempDir = await getTemporaryDirectory();
      _currentPath = '${tempDir.path}/task_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

      _logger.info('Starting native recording to: $_currentPath');

      final result = await _channel.invokeMethod<bool>('startRecording', {
        'path': _currentPath,
      });

      if (result == true) {
        _isRecording = true;
        _logger.info('Native recording started successfully');
        return true;
      } else {
        _logger.error('Failed to start native recording', null, null);
        return false;
      }
    } catch (e) {
      _logger.error('Error starting recording', e, null);
      _currentPath = null;
      return false;
    }
  }

  /// Stop recording and return the file path
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      _logger.warning('Not recording');
      return null;
    }

    try {
      _logger.info('Stopping native recording...');

      final result = await _channel.invokeMethod<String>('stopRecording');
      _isRecording = false;

      _logger.info('Native recording stopped, path: $result');

      final path = result ?? _currentPath;
      _currentPath = null;
      return path;
    } catch (e) {
      _logger.error('Error stopping recording', e, null);
      _isRecording = false;
      final path = _currentPath;
      _currentPath = null;
      return path;
    }
  }

  /// Dispose resources
  void dispose() {
    if (_isRecording) {
      stopRecording();
    }
  }
}
