import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/task_submission.dart';
import 'logger_service.dart';

/// Service for submitting session reports to the API
class ReportSubmissionService {
  static final ReportSubmissionService _instance = ReportSubmissionService._internal();
  factory ReportSubmissionService() => _instance;

  final _logger = LoggerService();

  // API Configuration
  static const String apiUrl = 'https://testreport.ssarchitects.ae/api/v1/submit_report.php';
  static const String authToken = 'e985666576fc298350682a2f2f1a8093d022d740aa96f0a9b72785a134cc2c95';

  ReportSubmissionService._internal();

  /// Submit a session report to the API
  ///
  /// [report] - The session report containing all task data
  Future<Map<String, dynamic>> submitReport(SessionReport report) async {
    try {
      _logger.info('Submitting session report for ${report.email} on ${report.date}...');

      // Create multipart request
      final request = http.MultipartRequest('POST', Uri.parse(apiUrl));

      // Add authorization header
      request.headers['Authorization'] = 'Bearer $authToken';

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
              _logger.info('Added attachment: $fileName for task $i');
            } else {
              _logger.warning('Attachment file not found: $filePath');
            }
          } catch (e) {
            _logger.error('Failed to add attachment: $filePath', e, null);
          }
        }
      }

      // Log all request fields for debugging
      _logger.info('Request fields: ${request.fields}');
      _logger.info('Number of files: ${request.files.length}');

      // Send the request
      _logger.info('Sending request to API...');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      // Log response
      _logger.info('API Response Status: ${response.statusCode}');
      _logger.info('API Response Body: ${response.body}');

      // Parse response
      if (response.statusCode == 200 || response.statusCode == 201) {
        _logger.info('Report submitted successfully');
        return {
          'success': true,
          'message': 'Report submitted successfully',
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
