import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'logger_service.dart';

/// Result from task extraction API
class ExtractedTask {
  final String title;
  final String description;

  const ExtractedTask({
    required this.title,
    required this.description,
  });
}

/// Service for extracting task details from audio using AI
class TaskExtractorService {
  static final TaskExtractorService _instance = TaskExtractorService._internal();
  factory TaskExtractorService() => _instance;

  final _logger = LoggerService();

  // AI API endpoint for task extraction
  static const String _apiUrl = 'https://ai.ssapp.site/api/v1/task-extractor/extract';

  TaskExtractorService._internal();

  /// Extract task title and description from an audio file
  ///
  /// [audioFile] - The recorded audio file
  /// Returns [ExtractedTask] on success, throws on failure
  Future<ExtractedTask> extractTaskFromAudio(File audioFile) async {
    try {
      _logger.info('Extracting task from audio file: ${audioFile.path}');

      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));

      // Get filename and extension
      final filename = audioFile.path.split(Platform.pathSeparator).last;
      final extension = filename.split('.').last.toLowerCase();
      final contentType = _getAudioContentType(extension);

      // Add audio file
      request.files.add(
        await http.MultipartFile.fromPath(
          'audio',
          audioFile.path,
          filename: filename,
          contentType: MediaType.parse(contentType),
        ),
      );

      _logger.info('Sending audio to AI API (content-type: $contentType)...');

      // Send request with extended timeout
      final client = http.Client();
      try {
        final streamedResponse = await request.send().timeout(
          const Duration(minutes: 2),
          onTimeout: () {
            throw Exception('Request timed out. Please try again.');
          },
        );
        final response = await http.Response.fromStream(streamedResponse);

        _logger.info('Task extractor response status: ${response.statusCode}');
        _logger.info('Task extractor response body: ${response.body}');

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = json.decode(response.body) as Map<String, dynamic>;

          // Check for API error
          if (data['success'] == false) {
            final errorMessage = data['error'] as String? ?? 'Failed to extract task from audio';
            _logger.error('API returned error: $errorMessage', null, null);
            throw Exception(errorMessage);
          }

          final title = data['title'] as String?;
          final description = data['description'] as String?;

          if (title == null || description == null) {
            _logger.error('Missing title or description in response', null, null);
            throw Exception('Could not extract task details from audio');
          }

          _logger.info('Successfully extracted task: "$title"');
          return ExtractedTask(
            title: title,
            description: description,
          );
        } else {
          _logger.error('API request failed: ${response.statusCode} - ${response.body}', null, null);
          throw Exception('Failed to process audio: ${response.statusCode}');
        }
      } finally {
        client.close();
      }
    } catch (e, stackTrace) {
      _logger.error('Error extracting task from audio', e, stackTrace);
      rethrow;
    }
  }

  /// Get the appropriate content type for the audio file extension
  String _getAudioContentType(String extension) {
    switch (extension) {
      case 'm4a':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'opus':
        return 'audio/opus';
      case 'webm':
        return 'audio/webm';
      case 'pcm':
        return 'audio/L16'; // PCM 16-bit audio
      default:
        return 'audio/mpeg';
    }
  }
}
