import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';
import '../core/extensions/context_extensions.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/date_time_utils.dart';
import '../models/project.dart';
import '../models/task_submission.dart';
import '../providers/auth_provider.dart';
import '../providers/task_provider.dart';
import '../services/report_submission_service.dart';
import '../services/window_service.dart';
import '../widgets/gradient_button.dart';

class SubmissionFormScreen extends ConsumerStatefulWidget {
  final List<Project> projects;

  const SubmissionFormScreen({super.key, required this.projects});

  @override
  ConsumerState<SubmissionFormScreen> createState() =>
      _SubmissionFormScreenState();
}

class _SubmissionFormScreenState extends ConsumerState<SubmissionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reportSubmissionService = ReportSubmissionService();
  final _windowService = WindowService();

  // Map of project ID to list of tasks for that project
  late Map<String, List<TaskFormData>> _projectTasks;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _windowService.setDashboardWindowSize();
    _initializeFormData();
  }

  void _initializeFormData() {
    _projectTasks = {};
    // Initialize with tasks for each project that has time tracked
    for (var project in widget.projects.where(
      (p) => p.totalTime.inSeconds > 0,
    )) {
      // Get pre-added tasks from the provider
      final preAddedTasks = ref.read(projectTasksProvider(project.id));

      if (preAddedTasks.isNotEmpty) {
        // Create TaskFormData from pre-added tasks
        _projectTasks[project.id] = preAddedTasks
            .map(
              (task) => TaskFormData(
                taskNameController: TextEditingController(text: task.taskName),
                taskDescController: TextEditingController(),
                attachments: [],
              ),
            )
            .toList();
      } else {
        // Fallback: create one empty task if no pre-added tasks
        _projectTasks[project.id] = [
          TaskFormData(
            taskNameController: TextEditingController(),
            taskDescController: TextEditingController(),
            attachments: [],
          ),
        ];
      }
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
        type:
            FileType.any, // Changed from custom to any for better compatibility
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
      _projectTasks[projectId]![taskIndex].attachments.removeAt(
        attachmentIndex,
      );
    });
  }

  Future<void> _takeScreenshot(String projectId, int taskIndex) async {
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
          _projectTasks[projectId]![taskIndex].attachments.add(screenshotPath);
        });
        if (mounted) {
          context.showSuccessSnackBar('Screenshot captured');
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

      for (var project in widget.projects.where(
        (p) => p.totalTime.inSeconds > 0,
      )) {
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
          // Clear all persisted tasks after successful submission
          await ref.read(tasksProvider.notifier).clearAllTasks();
          context.showSuccessSnackBar('Report submitted successfully!');
          Navigator.of(context).pop(true); // Return true to indicate success
        } else {
          context.showErrorSnackBar(
            result['message'] ?? 'Failed to submit report',
          );
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
    final projectsWithTime = widget.projects
        .where((p) => p.totalTime.inSeconds > 0)
        .toList();

    if (projectsWithTime.isEmpty) {
      return Scaffold(
        backgroundColor: AppTheme.surfaceColor,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 40.0, 16.0, 16.0),
          child: Column(
            children: [
              // Header with back button
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Submit Report',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.timer_off,
                        size: 48,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No project time to submit',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16.0, 40.0, 16.0, 16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with back button and summary
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Submit Report',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${projectsWithTime.length} project${projectsWithTime.length > 1 ? 's' : ''} • ${DateTimeUtils.formatDuration(_getTotalTime(projectsWithTime))}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Projects and tasks list
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: projectsWithTime.length,
                  itemBuilder: (context, projectIndex) {
                    return _buildProjectCard(projectsWithTime[projectIndex]);
                  },
                ),
              ),

              // Submit button
              const SizedBox(height: 12),
              GradientButton(
                onPressed: _isSubmitting ? null : _submitReport,
                height: 40,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send, size: 16, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Submit Report',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProjectCard(Project project) {
    final tasks = _projectTasks[project.id] ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project header (read-only)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      DateTimeUtils.formatDuration(project.totalTime),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              // Add Task button
              TextButton(
                onPressed: () => _addTask(project.id),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 14),
                    SizedBox(width: 4),
                    Text('Task', style: TextStyle(fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 16),

          // Tasks for this project
          ...tasks.asMap().entries.map((entry) {
            final taskIndex = entry.key;
            final taskData = entry.value;
            return _buildTaskForm(
              project.id,
              taskIndex,
              taskData,
              tasks.length,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTaskForm(
    String projectId,
    int taskIndex,
    TaskFormData taskData,
    int totalTasks,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Task header with delete button
          Row(
            children: [
              Text(
                'Task ${taskIndex + 1}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              if (totalTasks > 1)
                TextButton(
                  onPressed: () => _removeTask(projectId, taskIndex),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    foregroundColor: AppTheme.errorColor,
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Icon(Icons.delete_outline, size: 14)],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Task name field
          TextFormField(
            controller: taskData.taskNameController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Task Name',
              labelStyle: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 12,
              ),
              hintText: 'e.g., Design Review',
              hintStyle: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              isDense: true,
              filled: true,
              fillColor: AppTheme.backgroundColor,
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Required';
              }
              return null;
            },
          ),

          const SizedBox(height: 8),

          // Task description field
          TextFormField(
            controller: taskData.taskDescController,
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Description (Optional)',
              labelStyle: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 12,
              ),
              hintText: 'What you worked on...',
              hintStyle: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              isDense: true,
              filled: true,
              fillColor: AppTheme.backgroundColor,
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 8),

          // Attachments section with drag and drop
          _buildAttachmentsSection(projectId, taskIndex, taskData),
        ],
      ),
    );
  }

  Widget _buildAttachmentsSection(
    String projectId,
    int taskIndex,
    TaskFormData taskData,
  ) {
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
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: taskData.isDragging
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: taskData.isDragging
                ? AppTheme.primaryColor
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with buttons
            Row(
              children: [
                Text(
                  'Attachments',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _takeScreenshot(projectId, taskIndex),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.screenshot, size: 14),
                      SizedBox(width: 2),
                      Text('Screenshot', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () => _pickFiles(projectId, taskIndex),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file, size: 14),
                      SizedBox(width: 2),
                      Text('Files', style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ],
            ),

            // Drop zone hint (compact)
            if (taskData.attachments.isEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: taskData.isDragging
                      ? AppTheme.primaryColor.withValues(alpha: 0.2)
                      : AppTheme.backgroundColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: taskData.isDragging
                        ? AppTheme.primaryColor
                        : AppTheme.borderColor,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      taskData.isDragging
                          ? Icons.file_download
                          : Icons.cloud_upload_outlined,
                      size: 20,
                      color: taskData.isDragging
                          ? AppTheme.primaryColor
                          : AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      taskData.isDragging ? 'Drop here' : 'Drag & drop files',
                      style: TextStyle(
                        fontSize: 10,
                        color: taskData.isDragging
                            ? AppTheme.primaryColor
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // File previews (compact)
            if (taskData.attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 60,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: taskData.attachments.length,
                  itemBuilder: (context, attachmentIndex) {
                    final path = taskData.attachments[attachmentIndex];
                    final fileName = path.split(Platform.pathSeparator).last;
                    final isImage = _isImageFile(path);

                    return Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.only(right: 6),
                      child: Stack(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppTheme.borderColor),
                              color: AppTheme.backgroundColor,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: isImage
                                  ? Image.file(
                                      File(path),
                                      fit: BoxFit.cover,
                                      width: 60,
                                      height: 60,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return _buildFileIconCompact(
                                              fileName,
                                            );
                                          },
                                    )
                                  : _buildFileIconCompact(fileName),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: GestureDetector(
                              onTap: () => _removeAttachment(
                                projectId,
                                taskIndex,
                                attachmentIndex,
                              ),
                              child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: AppTheme.errorColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 10,
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

  Widget _buildFileIconCompact(String fileName) {
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
        Icon(iconData, size: 20, color: iconColor),
        const SizedBox(height: 2),
        Text(
          fileName.length > 8 ? '${fileName.substring(0, 6)}...' : fileName,
          style: const TextStyle(fontSize: 7),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
    return [
      'jpg',
      'jpeg',
      'png',
      'gif',
      'bmp',
      'webp',
      'heic',
      'heif',
    ].contains(extension);
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
