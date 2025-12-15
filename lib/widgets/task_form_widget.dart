import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../core/theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import 'gradient_button.dart';

/// Callback when a task is successfully submitted
typedef OnTaskSubmitted = void Function(String taskName, String description);

/// Inline task form widget for submitting tasks
/// Can be used inside dialogs or cards
class TaskFormWidget extends StatefulWidget {
  final String projectId;
  final OnTaskSubmitted onTaskSubmitted;
  final VoidCallback? onCancel;
  final bool showCancelButton;
  final bool compact;

  const TaskFormWidget({
    super.key,
    required this.projectId,
    required this.onTaskSubmitted,
    this.onCancel,
    this.showCancelButton = false,
    this.compact = true,
  });

  @override
  State<TaskFormWidget> createState() => _TaskFormWidgetState();
}

class _TaskFormWidgetState extends State<TaskFormWidget> {
  final _formKey = GlobalKey<FormState>();
  final _taskNameController = TextEditingController();
  final _taskDescController = TextEditingController();
  final _logger = LoggerService();
  final _api = ApiService();

  final List<PlatformFile> _attachments = [];
  bool _isSubmitting = false;

  // File constraints
  static const int maxFiles = 5;
  static const int maxFileSizeBytes = 5 * 1024 * 1024; // 5MB
  static const int maxTotalSizeBytes = 25 * 1024 * 1024; // 25MB
  static const List<String> allowedExtensions = ['png', 'jpg', 'jpeg', 'pdf'];

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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      // Convert PlatformFiles to Files
      final files = _attachments
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();

      await _api.createDailyReport(
        projectId: widget.projectId,
        taskName: _taskNameController.text.trim(),
        taskDescription: _taskDescController.text.trim(),
        attachments: files.isNotEmpty ? files : null,
      );

      final taskName = _taskNameController.text.trim();
      final description = _taskDescController.text.trim();

      _logger.info('Task submitted for project: ${widget.projectId}');

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

          // Task Description
          TextFormField(
            controller: _taskDescController,
            decoration: InputDecoration(
              labelText: 'Description *',
              hintText: 'Describe what you accomplished...',
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
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Description is required';
              }
              return null;
            },
          ),
          SizedBox(height: verticalSpacing),

          // Attachments Section
          Row(
            children: [
              Text(
                'Attachments',
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

          // Attachment Chips
          if (_attachments.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_attachments.length, (index) {
                final file = _attachments[index];
                return Chip(
                  label: Text(
                    file.name,
                    style: const TextStyle(fontSize: 11),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 14),
                  onDeleted: () => _removeAttachment(index),
                  backgroundColor: AppTheme.backgroundColor,
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }),
            ),

          // Add Attachment Button
          if (_attachments.length < maxFiles)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.attach_file, size: 16),
                label: const Text('Add Attachments', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
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
