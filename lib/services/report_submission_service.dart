import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/task_submission.dart';
import 'logger_service.dart';
import 'storage_service.dart';
import 'api_service.dart';

/// Service for submitting session reports to the API
class ReportSubmissionService {
  static final ReportSubmissionService _instance = ReportSubmissionService._internal();
  factory ReportSubmissionService() => _instance;

  final _logger = LoggerService();
  final _storage = StorageService();
  final _api = ApiService();

  // API Configuration - loaded from .env
  static String get _apiUrl =>
      '${dotenv.env['API_BASE_URL'] ?? 'https://app.ssarchitects.ae/api/v1'}/reports/daily-reports';

  ReportSubmissionService._internal();

  /// Get project ID by matching project name
  /// First checks cached projects, then fetches from API if needed
  Future<String?> _getProjectIdByName(String projectName) async {
    try {
      // First check cached projects in storage
      final cachedProjects = _storage.getAllProjects();
      for (final project in cachedProjects) {
        if (project.name.toLowerCase() == projectName.toLowerCase()) {
          return project.id;
        }
      }

      // If not found in cache, fetch from API
      _logger.info('Project "$projectName" not in cache, fetching from API...');
      final projectsJson = await _api.getProjects();

      for (final json in projectsJson) {
        final name = (json['name'] ?? json['project_name'] ?? json['ProjectName'] ?? '') as String;
        if (name.toLowerCase() == projectName.toLowerCase()) {
          final id = (json['_id'] ?? json['id'] ?? json['project_id'] ?? json['ProjectID'] ?? '').toString();
          if (id.isNotEmpty) {
            return id;
          }
        }
      }

      _logger.warning('Could not find project ID for: $projectName');
      return null;
    } catch (e) {
      _logger.error('Error looking up project ID for: $projectName', e, null);
      return null;
    }
  }

  /// Submit a session report to the API
  ///
  /// [report] - The session report containing all task data
  Future<Map<String, dynamic>> submitReport(SessionReport report) async {
    _logger.info('Submitting session report for ${report.email} on ${report.date}...');

    try {
      // Get user's auth token
      final user = _storage.getCurrentUser();
      if (user == null || user.token == null) {
        _logger.error('No authenticated user found', null, null);
        return {
          'success': false,
          'message': 'Error: User not authenticated',
          'response': null,
        };
      }

      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));

      // Add authorization header with user's token
      request.headers['Authorization'] = 'Bearer ${user.token}';

      // Add orientation
      request.fields['orientation'] = report.orientation;

      // Build tasks array with project IDs
      final tasksJson = <Map<String, dynamic>>[];

      for (int i = 0; i < report.tasks.length; i++) {
        final task = report.tasks[i];

        // Look up project ID by name
        final projectId = await _getProjectIdByName(task.projectName);

        if (projectId == null) {
          _logger.warning('Could not find project ID for "${task.projectName}", skipping task');
          continue;
        }

        tasksJson.add({
          'projectId': projectId,
          'title': task.taskName.isNotEmpty ? task.taskName : 'Work on ${task.projectName}',
          'description': task.taskDescription.isNotEmpty ? task.taskDescription : 'Work on ${task.projectName}',
          'meta': {}, // Empty meta object for now
        });

        // Add attachments for this task
        for (int j = 0; j < task.attachmentPaths.length; j++) {
          final filePath = task.attachmentPaths[j];
          try {
            final file = File(filePath);
            if (await file.exists()) {
              // Sanitize filename to avoid "multiple extensions not allowed" error
              // Extract only the last extension and create a clean filename
              final originalName = file.path.split('/').last;
              final lastDotIndex = originalName.lastIndexOf('.');
              final extension = lastDotIndex != -1 ? originalName.substring(lastDotIndex) : '';
              final sanitizedFileName = 'attachment_${i}_$j$extension';

              request.files.add(
                await http.MultipartFile.fromPath(
                  'taskAttachments_$i',
                  file.path,
                  filename: sanitizedFileName,
                ),
              );
              _logger.info('Added attachment: $sanitizedFileName (original: $originalName) for task $i');
            } else {
              _logger.warning('Attachment file not found: $filePath');
            }
          } catch (e) {
            _logger.error('Failed to add attachment: $filePath', e, null);
          }
        }
      }

      // Add tasks JSON to request
      request.fields['tasks'] = jsonEncode(tasksJson);

      // Log all request fields for debugging
      _logger.info('Request fields: ${request.fields}');
      _logger.info('Number of files: ${request.files.length}');

      // Send the request
      _logger.info('Sending request to API...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Log response
      _logger.info('Response Status: ${response.statusCode}');
      _logger.info('Response Body: ${response.body}');

      // Parse response
      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('Report submitted successfully');
        return {
          'success': true,
          'message': 'Report submitted successfully',
          'response': response.body,
        };
      } else if (response.statusCode == 401) {
        _logger.error('Unauthorized - user may need to re-login', null, null);
        return {
          'success': false,
          'message': 'Error: Unauthorized - please login again',
          'response': response.body,
        };
      } else {
        _logger.error('Report submission failed with status ${response.statusCode}', null, null);
        return {
          'success': false,
          'message': 'Failed to submit report: ${response.statusCode}',
          'response': response.body,
        };
      }
    } catch (e, stackTrace) {
      _logger.error('Error submitting report', e, stackTrace);
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
        'response': null,
      };
    }
  }
}
