import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../core/extensions/context_extensions.dart';
import '../core/utils/date_time_utils.dart';
import '../models/project.dart';
import '../models/task_submission.dart';
import '../providers/auth_provider.dart';
import '../services/report_submission_service.dart';

class SubmissionFormScreen extends ConsumerStatefulWidget {
  final List<Project> projects;

  const SubmissionFormScreen({
    super.key,
    required this.projects,
  });

  @override
  ConsumerState<SubmissionFormScreen> createState() => _SubmissionFormScreenState();
}

class _SubmissionFormScreenState extends ConsumerState<SubmissionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reportSubmissionService = ReportSubmissionService();

  // Map of project ID to list of tasks for that project
  late Map<String, List<TaskFormData>> _projectTasks;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _initializeFormData();
  }

  void _initializeFormData() {
    _projectTasks = {};
    // Initialize with one task per project that has time tracked
    for (var project in widget.projects.where((p) => p.totalTime.inSeconds > 0)) {
      _projectTasks[project.id] = [
        TaskFormData(
          taskNameController: TextEditingController(),
          taskDescController: TextEditingController(),
          attachments: [],
        ),
      ];
    }
  }

  @override
  void dispose() {
    // Dispose all controllers
    for (var tasks in _projectTasks.values) {
      for (var task in tasks) {
        task.taskNameController.dispose();
        task.taskDescController.dispose();
      }
    }
    super.dispose();
  }

  void _addTask(String projectId) {
    setState(() {
      _projectTasks[projectId]!.add(
        TaskFormData(
          taskNameController: TextEditingController(),
          taskDescController: TextEditingController(),
          attachments: [],
        ),
      );
    });
  }

  void _removeTask(String projectId, int taskIndex) {
    if (_projectTasks[projectId]!.length <= 1) {
      context.showErrorSnackBar('Each project must have at least one task');
      return;
    }

    setState(() {
      final task = _projectTasks[projectId]!.removeAt(taskIndex);
      task.taskNameController.dispose();
      task.taskDescController.dispose();
    });
  }

  Future<void> _pickFiles(String projectId, int taskIndex) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any, // Changed from custom to any for better compatibility
      );

      if (result != null && result.files.isNotEmpty) {
        final List<String> filePaths = [];

        // Get file paths from picked files
        for (var file in result.files) {
          if (file.path != null) {
            filePaths.add(file.path!);
          }
        }

        if (filePaths.isNotEmpty) {
          setState(() {
            _projectTasks[projectId]![taskIndex].attachments.addAll(filePaths);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Error picking files: $e');
      }
    }
  }

  void _removeAttachment(String projectId, int taskIndex, int attachmentIndex) {
    setState(() {
      _projectTasks[projectId]![taskIndex].attachments.removeAt(attachmentIndex);
    });
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate()) {
      context.showErrorSnackBar('Please fill in all required fields');
      return;
    }

    // Check if at least one task has a name
    bool hasTaskName = false;
    for (var tasks in _projectTasks.values) {
      for (var task in tasks) {
        if (task.taskNameController.text.trim().isNotEmpty) {
          hasTaskName = true;
          break;
        }
      }
      if (hasTaskName) break;
    }

    if (!hasTaskName) {
      context.showErrorSnackBar('Please provide at least one task name');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final user = ref.read(currentUserProvider);
      if (user == null) {
        throw Exception('User not logged in');
      }

      // Create task submissions - flatten the map
      final List<TaskSubmission> allTasks = [];

      for (var project in widget.projects.where((p) => p.totalTime.inSeconds > 0)) {
        final tasks = _projectTasks[project.id] ?? [];
        for (var taskData in tasks) {
          allTasks.add(
            TaskSubmission(
              projectName: project.name,
              taskName: taskData.taskNameController.text.trim(),
              taskDescription: taskData.taskDescController.text.trim(),
              attachmentPaths: taskData.attachments,
            ),
          );
        }
      }

      // Create session report
      final report = SessionReport(
        email: user.email,
        date: DateTime.now(),
        orientation: 'l', // landscape by default
        tasks: allTasks,
      );

      // Submit report
      final result = await _reportSubmissionService.submitReport(report);

      if (mounted) {
        if (result['success'] == true) {
          context.showSuccessSnackBar('Report submitted successfully!');
          Navigator.of(context).pop(true); // Return true to indicate success
        } else {
          context.showErrorSnackBar(result['message'] ?? 'Failed to submit report');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Error submitting report: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final projectsWithTime = widget.projects.where((p) => p.totalTime.inSeconds > 0).toList();

    if (projectsWithTime.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Submit Session Report'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No project time to submit',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Submit Session Report'),
        elevation: 2,
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            // Summary header
            Container(
              padding: const EdgeInsets.all(16),
              color: context.colorScheme.primary.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(Icons.assessment, color: context.colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Session Summary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${projectsWithTime.length} project${projectsWithTime.length > 1 ? 's' : ''} - Total: ${DateTimeUtils.formatDuration(_getTotalTime(projectsWithTime))}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Projects and tasks list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: projectsWithTime.length,
                itemBuilder: (context, projectIndex) {
                  return _buildProjectCard(projectsWithTime[projectIndex]);
                },
              ),
            ),

            // Submit button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitReport,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit Report',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(Project project) {
    final tasks = _projectTasks[project.id] ?? [];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Project header (read-only)
            Row(
              children: [
                Icon(
                  Icons.apartment,
                  color: context.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Time: ${DateTimeUtils.formatDuration(project.totalTime)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                // Add Task button
                TextButton.icon(
                  onPressed: () => _addTask(project.id),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Task'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.colorScheme.primary,
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Tasks for this project
            ...tasks.asMap().entries.map((entry) {
              final taskIndex = entry.key;
              final taskData = entry.value;
              return _buildTaskForm(project.id, taskIndex, taskData, tasks.length);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskForm(String projectId, int taskIndex, TaskFormData taskData, int totalTasks) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Task header with remove button
          Row(
            children: [
              Text(
                'Task ${taskIndex + 1}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (totalTasks > 1)
                IconButton(
                  onPressed: () => _removeTask(projectId, taskIndex),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red[400],
                  tooltip: 'Remove Task',
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Task name field
          TextFormField(
            controller: taskData.taskNameController,
            decoration: const InputDecoration(
              labelText: 'Task Name *',
              hintText: 'e.g., Design Review, Implementation',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.task_alt),
              filled: true,
              fillColor: Colors.white,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Task name is required';
              }
              return null;
            },
          ),

          const SizedBox(height: 12),

          // Task description field
          TextFormField(
            controller: taskData.taskDescController,
            decoration: const InputDecoration(
              labelText: 'Task Description (Optional)',
              hintText: 'Describe what you worked on...',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.description),
              filled: true,
              fillColor: Colors.white,
            ),
            maxLines: 3,
          ),

          const SizedBox(height: 12),

          // Attachments section
          Row(
            children: [
              const Text(
                'Attachments',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _pickFiles(projectId, taskIndex),
                icon: const Icon(Icons.attach_file, size: 16),
                label: const Text('Add Files', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),

          if (taskData.attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: taskData.attachments.asMap().entries.map((entry) {
                final attachmentIndex = entry.key;
                final path = entry.value;
                final fileName = path.split(Platform.pathSeparator).last;

                return Chip(
                  avatar: const Icon(Icons.insert_drive_file, size: 16),
                  label: Text(
                    fileName,
                    style: const TextStyle(fontSize: 11),
                  ),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _removeAttachment(projectId, taskIndex, attachmentIndex),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Duration _getTotalTime(List<Project> projects) {
    return projects.fold(
      Duration.zero,
      (total, project) => total + project.totalTime,
    );
  }
}

class TaskFormData {
  final TextEditingController taskNameController;
  final TextEditingController taskDescController;
  final List<String> attachments;

  TaskFormData({
    required this.taskNameController,
    required this.taskDescController,
    required this.attachments,
  });
}
