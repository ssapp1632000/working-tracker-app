import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:window_manager/window_manager.dart';
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

  Future<void> _takeScreenshot(String projectId, int taskIndex) async {
    try {
      // Create a unique filename with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempDir = Directory.systemTemp;
      final screenshotPath = '${tempDir.path}/screenshot_$timestamp.png';

      // Minimize the window before taking screenshot
      await windowManager.minimize();

      // Wait a moment for the window to minimize
      await Future.delayed(const Duration(milliseconds: 300));

      // Use macOS screencapture command with interactive selection mode
      // -i: interactive mode (user selects area)
      final result = await Process.run('screencapture', ['-i', screenshotPath]);

      // Restore the window after screenshot
      await windowManager.restore();
      await windowManager.focus();

      if (result.exitCode == 0) {
        // Check if file was created (user might have cancelled)
        final file = File(screenshotPath);
        if (await file.exists()) {
          setState(() {
            _projectTasks[projectId]![taskIndex].attachments.add(screenshotPath);
          });
          if (mounted) {
            context.showSuccessSnackBar('Screenshot captured');
          }
        }
      } else {
        // User cancelled the screenshot
        if (mounted && result.exitCode != 1) {
          context.showErrorSnackBar('Failed to capture screenshot');
        }
      }
    } catch (e) {
      // Make sure to restore window even if there's an error
      await windowManager.restore();
      await windowManager.focus();

      if (mounted) {
        context.showErrorSnackBar('Error taking screenshot: $e');
      }
    }
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

          // Attachments section with drag and drop
          _buildAttachmentsSection(projectId, taskIndex, taskData),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(String projectId, int taskIndex, TaskFormData taskData) {
    return DropTarget(
      onDragDone: (details) {
        final List<String> filePaths = [];
        for (var file in details.files) {
          filePaths.add(file.path);
        }
        if (filePaths.isNotEmpty) {
          setState(() {
            taskData.attachments.addAll(filePaths);
          });
        }
      },
      onDragEntered: (details) {
        setState(() {
          taskData.isDragging = true;
        });
      },
      onDragExited: (details) {
        setState(() {
          taskData.isDragging = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: taskData.isDragging ? Colors.blue[50] : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: taskData.isDragging ? Colors.blue[400]! : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
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
                  onPressed: () => _takeScreenshot(projectId, taskIndex),
                  icon: const Icon(Icons.screenshot, size: 16),
                  label: const Text('Screenshot', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: () => _pickFiles(projectId, taskIndex),
                  icon: const Icon(Icons.attach_file, size: 16),
                  label: const Text('Add Files', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),

            // Drop zone hint
            if (taskData.attachments.isEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  color: taskData.isDragging ? Colors.blue[100] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: taskData.isDragging ? Colors.blue[400]! : Colors.grey[300]!,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      taskData.isDragging ? Icons.file_download : Icons.cloud_upload_outlined,
                      size: 32,
                      color: taskData.isDragging ? Colors.blue[600] : Colors.grey[500],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      taskData.isDragging ? 'Drop files here' : 'Drag & drop files here',
                      style: TextStyle(
                        fontSize: 13,
                        color: taskData.isDragging ? Colors.blue[700] : Colors.grey[600],
                        fontWeight: taskData.isDragging ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // File previews
            if (taskData.attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: taskData.attachments.length,
                  itemBuilder: (context, attachmentIndex) {
                    final path = taskData.attachments[attachmentIndex];
                    final fileName = path.split(Platform.pathSeparator).last;
                    final isImage = _isImageFile(path);

                    return Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(right: 8),
                      child: Stack(
                        children: [
                          // Preview container
                          Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                              color: Colors.grey[100],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: isImage
                                  ? Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      width: 100,
                                      height: 100,
                                      errorBuilder: (context, error, stackTrace) {
                                        return _buildFileIcon(fileName);
                                      },
                                    )
                                  : _buildFileIcon(fileName),
                            ),
                          ),
                          // Delete button overlay
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => _removeAttachment(projectId, taskIndex, attachmentIndex),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.red[400],
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Duration _getTotalTime(List<Project> projects) {
    return projects.fold(
      Duration.zero,
      (total, project) => total + project.totalTime,
    );
  }

  bool _isImageFile(String path) {
    final extension = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif'].contains(extension);
  }

  Widget _buildFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    IconData iconData;
    Color iconColor;

    switch (extension) {
      case 'pdf':
        iconData = Icons.picture_as_pdf;
        iconColor = Colors.red;
        break;
      case 'doc':
      case 'docx':
        iconData = Icons.description;
        iconColor = Colors.blue;
        break;
      case 'xls':
      case 'xlsx':
        iconData = Icons.table_chart;
        iconColor = Colors.green;
        break;
      case 'zip':
      case 'rar':
      case '7z':
        iconData = Icons.folder_zip;
        iconColor = Colors.orange;
        break;
      default:
        iconData = Icons.insert_drive_file;
        iconColor = Colors.grey;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(iconData, size: 32, color: iconColor),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            fileName,
            style: const TextStyle(fontSize: 9),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class TaskFormData {
  final TextEditingController taskNameController;
  final TextEditingController taskDescController;
  final List<String> attachments;
  bool isDragging;

  TaskFormData({
    required this.taskNameController,
    required this.taskDescController,
    required this.attachments,
    this.isDragging = false,
  });
}
