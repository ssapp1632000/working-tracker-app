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

  // Old API Configuration
  static const String _oldApiUrl = 'https://testreport.ssarchitects.ae/api/v1/submit_report.php';
  static const String _oldAuthToken = 'e985666576fc298350682a2f2f1a8093d022d740aa96f0a9b72785a134cc2c95';

  // New API Configuration - loaded from .env
  static String get _newApiUrl =>
      '${dotenv.env['API_BASE_URL'] ?? 'https://api.ssapp.site/api/v1'}/reports/daily-reports';

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

  /// Submit a session report to BOTH old and new APIs
  ///
  /// [report] - The session report containing all task data
  Future<Map<String, dynamic>> submitReport(SessionReport report) async {
    _logger.info('Submitting session report for ${report.email} on ${report.date}...');

    // Submit to both APIs
    final oldResult = await _submitToOldApi(report);
    final newResult = await _submitToNewApi(report);

    // Log results
    _logger.info('Old API result: ${oldResult['success']}');
    _logger.info('New API result: ${newResult['success']}');

    // Return combined result (success if at least one succeeded)
    final overallSuccess = oldResult['success'] == true || newResult['success'] == true;

    return {
      'success': overallSuccess,
      'message': overallSuccess
          ? 'Report submitted successfully'
          : 'Failed to submit report to both APIs',
      'oldApiResult': oldResult,
      'newApiResult': newResult,
    };
  }

  /// Submit to the OLD API (testreport.ssarchitects.ae)
  Future<Map<String, dynamic>> _submitToOldApi(SessionReport report) async {
    try {
      _logger.info('Submitting to OLD API...');

      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_oldApiUrl));

      // Add authorization header
      request.headers['Authorization'] = 'Bearer $_oldAuthToken';

      // Add form fields
      request.fields['email'] = report.email;
      request.fields['date'] = report.toJson()['date'];
      request.fields['orientation'] = report.orientation;

      if (report.department != null && report.department!.isNotEmpty) {
        request.fields['department'] = report.department!;
      }

      // Add task data
      for (int i = 0; i < report.tasks.length; i++) {
        final task = report.tasks[i];

        // Add project name
        request.fields['taskProjects[$i]'] = task.projectName;

        // Add task name
        request.fields['taskNames[$i]'] = task.taskName.isNotEmpty ? task.taskName : 'Work on ${task.projectName}';

        // Add task description (optional)
        if (task.taskDescription.isNotEmpty) {
          request.fields['taskDescs[$i]'] = task.taskDescription;
        }

        // Add attachments for this task
        for (String filePath in task.attachmentPaths) {
          try {
            final file = File(filePath);
            if (await file.exists()) {
              final fileName = file.path.split('/').last;
              request.files.add(
                await http.MultipartFile.fromPath(
                  'taskImages[$i][]',
                  file.path,
                  filename: fileName,
                ),
              );
              _logger.info('Old API: Added attachment: $fileName for task $i');
            } else {
              _logger.warning('Old API: Attachment file not found: $filePath');
            }
          } catch (e) {
            _logger.error('Old API: Failed to add attachment: $filePath', e, null);
          }
        }
      }

      // Log all request fields for debugging
      _logger.info('Old API Request fields: ${request.fields}');
      _logger.info('Old API Number of files: ${request.files.length}');

      // Send the request
      _logger.info('Sending request to OLD API...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Log response
      _logger.info('Old API Response Status: ${response.statusCode}');
      _logger.info('Old API Response Body: ${response.body}');

      // Parse response
      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('Old API: Report submitted successfully');
        return {
          'success': true,
          'message': 'Report submitted successfully to old API',
          'response': response.body,
        };
      } else {
        _logger.error('Old API: Report submission failed with status ${response.statusCode}', null, null);
        return {
          'success': false,
          'message': 'Failed to submit report to old API: ${response.statusCode}',
          'response': response.body,
        };
      }
    } catch (e, stackTrace) {
      _logger.error('Old API: Error submitting report', e, stackTrace);
      return {
        'success': false,
        'message': 'Old API Error: ${e.toString()}',
        'response': null,
      };
    }
  }

  /// Submit to the NEW API (intercompany ngrok endpoint)
  Future<Map<String, dynamic>> _submitToNewApi(SessionReport report) async {
    try {
      _logger.info('Submitting to NEW API...');

      // Get user's auth token
      final user = _storage.getCurrentUser();
      if (user == null || user.token == null) {
        _logger.error('New API: No authenticated user found', null, null);
        return {
          'success': false,
          'message': 'New API Error: User not authenticated',
          'response': null,
        };
      }

      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(_newApiUrl));

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
          _logger.warning('New API: Could not find project ID for "${task.projectName}", skipping task');
          continue;
        }

        tasksJson.add({
          'projectId': projectId,
          'title': task.taskName.isNotEmpty ? task.taskName : 'Work on ${task.projectName}',
          'description': task.taskDescription.isNotEmpty ? task.taskDescription : 'Work on ${task.projectName}',
          'meta': {}, // Empty meta object for now
        });

        // Add attachments for this task
        for (String filePath in task.attachmentPaths) {
          try {
            final file = File(filePath);
            if (await file.exists()) {
              final fileName = file.path.split('/').last;
              request.files.add(
                await http.MultipartFile.fromPath(
                  'taskAttachments_$i',
                  file.path,
                  filename: fileName,
                ),
              );
              _logger.info('New API: Added attachment: $fileName for task $i');
            } else {
              _logger.warning('New API: Attachment file not found: $filePath');
            }
          } catch (e) {
            _logger.error('New API: Failed to add attachment: $filePath', e, null);
          }
        }
      }

      // Add tasks JSON to request
      request.fields['tasks'] = jsonEncode(tasksJson);

      // Log all request fields for debugging
      _logger.info('New API Request fields: ${request.fields}');
      _logger.info('New API Number of files: ${request.files.length}');

      // Send the request
      _logger.info('Sending request to NEW API...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Log response
      _logger.info('New API Response Status: ${response.statusCode}');
      _logger.info('New API Response Body: ${response.body}');

      // Parse response
      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('New API: Report submitted successfully');
        return {
          'success': true,
          'message': 'Report submitted successfully to new API',
          'response': response.body,
        };
      } else if (response.statusCode == 401) {
        _logger.error('New API: Unauthorized - user may need to re-login', null, null);
        return {
          'success': false,
          'message': 'New API Error: Unauthorized - please login again',
          'response': response.body,
        };
      } else {
        _logger.error('New API: Report submission failed with status ${response.statusCode}', null, null);
        return {
          'success': false,
          'message': 'Failed to submit report to new API: ${response.statusCode}',
          'response': response.body,
        };
      }
    } catch (e, stackTrace) {
      _logger.error('New API: Error submitting report', e, stackTrace);
      return {
        'success': false,
        'message': 'New API Error: ${e.toString()}',
        'response': null,
      };
    }
  }
}
