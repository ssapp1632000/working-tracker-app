import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';
import '../core/theme/app_theme.dart';
import '../providers/task_provider.dart';
import '../providers/project_provider.dart';
import '../providers/auth_provider.dart';
import '../services/report_submission_service.dart';
import '../services/logger_service.dart';
import '../models/task_submission.dart';
import 'gradient_button.dart';

/// Callback when a task is successfully submitted
typedef OnTaskSubmitted = void Function(String taskName, String description);

/// Inline task form widget for submitting tasks
/// Can be used inside dialogs or cards
class TaskFormWidget extends ConsumerStatefulWidget {
  final String projectId;
  final OnTaskSubmitted onTaskSubmitted;
  final VoidCallback? onCancel;
  final bool showCancelButton;
  final bool compact;
  final String? initialTaskName;

  const TaskFormWidget({
    super.key,
    required this.projectId,
    required this.onTaskSubmitted,
    this.onCancel,
    this.showCancelButton = false,
    this.compact = true,
    this.initialTaskName,
  });

  @override
  ConsumerState<TaskFormWidget> createState() => _TaskFormWidgetState();
}

class _TaskFormWidgetState extends ConsumerState<TaskFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _taskNameController = TextEditingController();
  final _taskDescController = TextEditingController();
  final _logger = LoggerService();

  final List<PlatformFile> _attachments = [];
  bool _isSubmitting = false;

  // File constraints
  static const int maxFiles = 5;
  static const int maxFileSizeBytes = 5 * 1024 * 1024; // 5MB
  static const int maxTotalSizeBytes = 25 * 1024 * 1024; // 25MB
  static const List<String> allowedExtensions = ['png', 'jpg', 'jpeg', 'pdf'];

  @override
  void initState() {
    super.initState();
    // Pre-fill task name if provided (for pending local tasks)
    if (widget.initialTaskName != null) {
      _taskNameController.text = widget.initialTaskName!;
    }
  }

  @override
  void dispose() {
    _taskNameController.dispose();
    _taskDescController.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: true,
      );

      if (result != null && result.files.isNotEmpty) {
        // Check file count
        final totalFiles = _attachments.length + result.files.length;
        if (totalFiles > maxFiles) {
          _showError('Maximum $maxFiles files allowed');
          return;
        }

        // Validate each file
        for (final file in result.files) {
          if (file.size > maxFileSizeBytes) {
            _showError('File "${file.name}" exceeds 5MB limit');
            return;
          }
        }

        // Check total size
        final currentSize = _attachments.fold<int>(0, (sum, f) => sum + f.size);
        final newSize = result.files.fold<int>(0, (sum, f) => sum + f.size);
        if (currentSize + newSize > maxTotalSizeBytes) {
          _showError('Total file size exceeds 25MB limit');
          return;
        }

        setState(() {
          _attachments.addAll(result.files);
        });
      }
    } catch (e) {
      _logger.error('Error picking files', e, null);
      _showError('Failed to pick files');
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isImageFile(String path) {
    final extension = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif']
        .contains(extension);
  }

  Widget _buildFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    IconData iconData;
    Color iconColor;

    switch (extension) {
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        iconColor = AppTheme.errorColor;
        break;
      case 'doc':
      case 'docx':
        iconData = Icons.description;
        iconColor = AppTheme.primaryColor;
        break;
      default:
        iconData = Icons.insert_drive_file;
        iconColor = AppTheme.textSecondary;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(iconData, size: 24, color: iconColor),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            fileName.length > 10 ? '${fileName.substring(0, 8)}...' : fileName,
            style: const TextStyle(fontSize: 8),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Future<void> _takeScreenshot() async {
    try {
      // Minimize the window before taking screenshot
      await windowManager.minimize();

      // Wait a moment for the window to minimize
      await Future.delayed(const Duration(milliseconds: 300));

      // Use screen_capturer for cross-platform support (Windows, macOS, Linux)
      CapturedData? capturedData = await screenCapturer.capture(
        mode: CaptureMode.region, // Interactive region selection
      );

      // Restore the window after screenshot
      await windowManager.restore();
      await windowManager.focus();

      if (capturedData != null && capturedData.imageBytes != null) {
        // Save to temp file
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tempDir = Directory.systemTemp;
        final screenshotPath = '${tempDir.path}/screenshot_$timestamp.png';
        final file = File(screenshotPath);
        await file.writeAsBytes(capturedData.imageBytes!);

        setState(() {
          _attachments.add(PlatformFile(
            path: screenshotPath,
            name: 'screenshot_$timestamp.png',
            size: capturedData.imageBytes!.length,
          ));
        });

        if (mounted) {
          _showSuccess('Screenshot captured');
        }
      }
    } catch (e) {
      // Make sure to restore window even if there's an error
      await windowManager.restore();
      await windowManager.focus();

      _logger.error('Error taking screenshot', e, null);
      if (mounted) {
        _showError('Error taking screenshot: $e');
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Convert PlatformFiles to file paths
      final attachmentPaths = _attachments
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();

      final taskName = _taskNameController.text.trim();
      final description = _taskDescController.text.trim();

      // Get project name for old API
      final projects = ref.read(projectsProvider).valueOrNull ?? [];
      final project = projects.firstWhere(
        (p) => p.id == widget.projectId,
        orElse: () => projects.isNotEmpty ? projects.first : throw Exception('No projects found'),
      );
      final projectName = project.name;

      // Get user email for old API
      final user = ref.read(currentUserProvider);
      final email = user?.email ?? '';

      // Submit to BOTH APIs using ReportSubmissionService
      final reportService = ReportSubmissionService();
      final taskSubmission = TaskSubmission(
        projectName: projectName,
        taskName: taskName,
        taskDescription: description,
        attachmentPaths: attachmentPaths,
      );

      final report = SessionReport(
        email: email,
        date: DateTime.now(),
        orientation: 'l',
        tasks: [taskSubmission],
      );

      final result = await reportService.submitReport(report);

      if (result['success'] != true) {
        throw Exception(result['message'] ?? 'Failed to submit task');
      }

      // Also create a local task so it appears in the dashboard
      try {
        await ref.read(tasksProvider.notifier).createTask(
          projectId: widget.projectId,
          taskName: taskName,
        );
        _logger.info('Local task created for dashboard display');
      } catch (e) {
        // Don't fail the submission if local task creation fails
        _logger.warning('Could not create local task: $e');
      }

      _logger.info('Task submitted to both APIs for project: ${widget.projectId}');

      // Clear form
      _taskNameController.clear();
      _taskDescController.clear();
      setState(() {
        _attachments.clear();
        _isSubmitting = false;
      });

      // Notify parent
      widget.onTaskSubmitted(taskName, description);
    } catch (e) {
      _logger.error('Failed to submit task', e, null);
      if (mounted) {
        _showError('Failed to submit task: $e');
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final verticalSpacing = widget.compact ? 12.0 : 16.0;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Task Name
          TextFormField(
            controller: _taskNameController,
            decoration: InputDecoration(
              labelText: 'Task Name *',
              hintText: 'What did you work on?',
              hintStyle: TextStyle(
                color: Colors.grey[500],
                fontSize: widget.compact ? 13 : 14,
              ),
              isDense: widget.compact,
              contentPadding: widget.compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
                  : null,
            ),
            style: TextStyle(fontSize: widget.compact ? 13 : 14),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Task name is required';
              }
              return null;
            },
          ),
          SizedBox(height: verticalSpacing),

          // Task Description (optional)
          TextFormField(
            controller: _taskDescController,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'Describe what you accomplished... (optional)',
              hintStyle: TextStyle(
                color: Colors.grey[500],
                fontSize: widget.compact ? 13 : 14,
              ),
              alignLabelWithHint: true,
              isDense: widget.compact,
              contentPadding: widget.compact
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 12)
                  : null,
            ),
            style: TextStyle(fontSize: widget.compact ? 13 : 14),
            maxLines: widget.compact ? 3 : 4,
          ),
          SizedBox(height: verticalSpacing),

          // Attachments Section (optional)
          Row(
            children: [
              Text(
                'Attachments (optional)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${_attachments.length}/$maxFiles files',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Attachment Previews (horizontal scroll)
          if (_attachments.isNotEmpty)
            SizedBox(
              height: 70,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final file = _attachments[index];
                  final path = file.path;
                  final isImage = path != null && _isImageFile(path);

                  return Stack(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.borderColor),
                          color: AppTheme.backgroundColor,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: isImage
                              ? Image.file(
                                  File(path),
                                  fit: BoxFit.cover,
                                  width: 70,
                                  height: 70,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildFileIcon(file.name);
                                  },
                                )
                              : _buildFileIcon(file.name),
                        ),
                      ),
                      // Delete button
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => _removeAttachment(index),
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: AppTheme.errorColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

          if (_attachments.isNotEmpty) const SizedBox(height: 8),

          // Attachment Buttons Row - use Wrap for small screens
          if (_attachments.length < maxFiles)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                // Screenshot Button
                TextButton.icon(
                  onPressed: _takeScreenshot,
                  icon: const Icon(Icons.screenshot, size: 16),
                  label: const Text('Screenshot', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
                // Add Files Button
                TextButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: const Text('Files', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 4),
          Text(
            'Allowed: PNG, JPG, PDF (max 5MB each)',
            style: TextStyle(
              fontSize: 10,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: verticalSpacing),

          // Submit Button Row
          Row(
            children: [
              if (widget.showCancelButton && widget.onCancel != null) ...[
                TextButton(
                  onPressed: _isSubmitting ? null : widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const Spacer(),
              ] else
                const Spacer(),

              SizedBox(
                width: widget.compact ? 100 : 120,
                child: GradientButton(
                  onPressed: _isSubmitting ? null : _submit,
                  height: widget.compact ? 36 : 40,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'Submit Task',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: widget.compact ? 12 : 14,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
