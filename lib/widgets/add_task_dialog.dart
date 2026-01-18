import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:window_manager/window_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:image/image.dart' as img;
import '../core/theme/app_theme.dart';
import '../core/extensions/context_extensions.dart';
import '../providers/task_provider.dart';
import '../providers/attendance_provider.dart';
import '../services/logger_service.dart';
import '../services/task_extractor_service.dart';
import '../services/native_audio_recorder.dart';
import '../services/api_service.dart';
import '../models/project_with_time.dart';
import '../models/report_task.dart';

/// Result from the add task dialog
class AddTaskResult {
  final bool completed;
  final bool addedLater;
  final int tasksSubmitted;

  const AddTaskResult({
    this.completed = false,
    this.addedLater = false,
    this.tasksSubmitted = 0,
  });

  bool get shouldProceed => completed || addedLater;
}

/// Dialog for adding tasks before switching projects
/// Matches the mobile app design with "Add Your Tasks" title
class AddTaskDialog extends ConsumerStatefulWidget {
  final String projectId;
  final String projectName;
  final String? projectImage;
  final bool allowAddLater;

  const AddTaskDialog({
    super.key,
    required this.projectId,
    required this.projectName,
    this.projectImage,
    this.allowAddLater = true,
  });

  /// Show the dialog for project switch
  static Future<AddTaskResult?> show({
    required BuildContext context,
    required String projectId,
    required String projectName,
    String? projectImage,
    bool allowAddLater = true,
  }) {
    return showDialog<AddTaskResult>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => AddTaskDialog(
        projectId: projectId,
        projectName: projectName,
        projectImage: projectImage,
        allowAddLater: allowAddLater,
      ),
    );
  }

  /// Show from ProjectWithTime
  static Future<AddTaskResult?> showForProject({
    required BuildContext context,
    required ProjectWithTime project,
    bool allowAddLater = true,
  }) {
    return show(
      context: context,
      projectId: project.projectId,
      projectName: project.projectName,
      projectImage: project.imageUrl,
      allowAddLater: allowAddLater,
    );
  }

  @override
  ConsumerState<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends ConsumerState<AddTaskDialog> {
  void _onAddTask() async {
    final result = await AddTaskSheet.show(
      context: context,
      projectId: widget.projectId,
      projectName: widget.projectName,
      ref: ref,
    );

    if (result == true && mounted) {
      // Task was added successfully - auto-proceed with the switch
      Navigator.of(context).pop(AddTaskResult(
        completed: true,
        addedLater: false,
        tasksSubmitted: 1,
      ));
    }
  }

  void _onAddLater() {
    Navigator.of(context).pop(AddTaskResult(
      completed: false,
      addedLater: true,
      tasksSubmitted: 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.assignment_outlined,
                color: Color(0xFF7C6AFA),
                size: 28,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            const Text(
              'Add Your Tasks',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              'Before switching projects, please add the\ntasks you worked on for',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.6),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),

            // Project name
            Text(
              '"${widget.projectName}"',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF7C6AFA),
              ),
            ),
            const SizedBox(height: 24),

            // Add Task button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _onAddTask,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text(
                  'Add Task',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C6AFA),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Add Later button
            if (widget.allowAddLater)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _onAddLater,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Add Later',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}

/// Bottom sheet for adding or editing a task
class AddTaskSheet extends ConsumerStatefulWidget {
  final String projectId;
  final String projectName;
  /// Optional: time entry IDs for pending tasks (to mark as submitted after)
  /// For merged entries, this will contain all entry IDs.
  final List<String>? entryIds;
  /// Optional: report date for pending tasks
  final DateTime? reportDate;
  /// Callback when task is created (for pending tasks flow)
  final void Function(Map<String, dynamic> task)? onTaskCreated;
  /// Optional: task to edit (if provided, sheet is in edit mode)
  final ReportTask? taskToEdit;
  /// Callback when task is updated (for edit mode)
  final void Function(ReportTask updatedTask)? onTaskUpdated;

  const AddTaskSheet({
    super.key,
    required this.projectId,
    required this.projectName,
    this.entryIds,
    this.reportDate,
    this.onTaskCreated,
    this.taskToEdit,
    this.onTaskUpdated,
  });

  /// Check if we're in edit mode
  bool get isEditMode => taskToEdit != null;

  /// Show the bottom sheet for adding a new task
  /// If ref is provided, will check for check-in status first
  static Future<bool?> show({
    required BuildContext context,
    required String projectId,
    required String projectName,
    WidgetRef? ref,
    List<String>? entryIds,
    DateTime? reportDate,
    void Function(Map<String, dynamic> task)? onTaskCreated,
  }) {
    // Check if user is checked in (if ref is provided) - skip for pending tasks
    if (ref != null && (entryIds == null || entryIds.isEmpty)) {
      final attendance = ref.read(currentAttendanceProvider);
      final isCheckedIn = attendance?.isCurrentlyCheckedIn ?? false;

      if (!isCheckedIn) {
        context.showAlertDialog(
          title: 'Check In Required',
          content: 'Please check in from the mobile app first to add tasks.',
        );
        return Future.value(null);
      }
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddTaskSheet(
        projectId: projectId,
        projectName: projectName,
        entryIds: entryIds,
        reportDate: reportDate,
        onTaskCreated: onTaskCreated,
      ),
    );
  }

  /// Show the bottom sheet for editing an existing task
  static Future<bool?> showEdit({
    required BuildContext context,
    required String projectId,
    required String projectName,
    required ReportTask taskToEdit,
    void Function(ReportTask updatedTask)? onTaskUpdated,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddTaskSheet(
        projectId: projectId,
        projectName: projectName,
        taskToEdit: taskToEdit,
        onTaskUpdated: onTaskUpdated,
      ),
    );
  }

  @override
  ConsumerState<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends ConsumerState<AddTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _logger = LoggerService();
  final _taskExtractor = TaskExtractorService();

  final List<PlatformFile> _attachments = [];
  bool _isSubmitting = false;
  bool _isRecording = false;
  bool _isExtractingTask = false;
  bool _isProcessingMicTap = false;  // Guard against multiple taps
  NativeAudioRecorder? _audioRecorder;

  // File constraints
  static const int maxFiles = 5;

  @override
  void initState() {
    super.initState();
    // Ensure always-on-top is disabled (in case it was left on from previous crash)
    _resetWindowState();

    // If editing, populate fields with existing task data
    if (widget.isEditMode && widget.taskToEdit != null) {
      _titleController.text = widget.taskToEdit!.taskName;
      _descriptionController.text = widget.taskToEdit!.taskDescription;
    }
  }

  Future<void> _resetWindowState() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      try {
        await windowManager.setAlwaysOnTop(false);
      } catch (e) {
        // Ignore errors
      }
    }
  }
  static const int maxImageSizeBytes = 20 * 1024 * 1024; // 20MB for images
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50MB for files
  static const int maxTotalSizeBytes = 100 * 1024 * 1024; // 100MB total

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _cleanupRecorder();
    super.dispose();
  }

  Future<void> _cleanupRecorder() async {
    try {
      if (_audioRecorder != null) {
        if (_audioRecorder!.isRecording) {
          await _audioRecorder!.stopRecording();
        }
        _audioRecorder!.dispose();
        _audioRecorder = null;
      }
    } catch (e) {
      // Ignore cleanup errors
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'pdf'],
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
          final isImage = ['png', 'jpg', 'jpeg'].contains(
            file.extension?.toLowerCase(),
          );
          final maxSize = isImage ? maxImageSizeBytes : maxFileSizeBytes;
          if (file.size > maxSize) {
            final maxMB = maxSize ~/ (1024 * 1024);
            _showError('File "${file.name}" exceeds ${maxMB}MB limit');
            return;
          }
        }

        // Check total size
        final currentSize = _attachments.fold<int>(0, (sum, f) => sum + f.size);
        final newSize = result.files.fold<int>(0, (sum, f) => sum + f.size);
        if (currentSize + newSize > maxTotalSizeBytes) {
          _showError('Total file size exceeds 100MB limit');
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
        // Convert PNG to JPEG for smaller file size
        final image = img.decodeImage(capturedData.imageBytes!);
        if (image == null) {
          throw Exception('Failed to decode screenshot image');
        }
        final jpegBytes = img.encodeJpg(image, quality: 85);

        // Save to temp file
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tempDir = Directory.systemTemp;
        final screenshotPath = '${tempDir.path}/screenshot_$timestamp.jpg';
        final file = File(screenshotPath);
        await file.writeAsBytes(jpegBytes);

        setState(() {
          _attachments.add(PlatformFile(
            path: screenshotPath,
            name: 'screenshot_$timestamp.jpg',
            size: jpegBytes.length,
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

  bool _isImageFile(String path) {
    final extension = path.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(extension);
  }

  Future<void> _handleMicTap() async {
    // Guard against multiple rapid taps
    if (_isProcessingMicTap) {
      _logger.info('Mic tap ignored - already processing');
      return;
    }
    _isProcessingMicTap = true;

    _logger.info('Mic button tapped. isRecording=$_isRecording, isSubmitting=$_isSubmitting, isExtractingTask=$_isExtractingTask');
    try {
      if (_isRecording) {
        await _stopRecordingAndExtract();
      } else {
        await _startRecording();
      }
    } finally {
      _isProcessingMicTap = false;
    }
  }

  Future<void> _startRecording() async {
    try {
      _logger.info('Starting recording process...');

      // Create recorder instance
      _audioRecorder = NativeAudioRecorder();

      // Check permission
      final hasPermission = await _audioRecorder!.hasPermission();
      _logger.info('Permission result: $hasPermission');

      if (!hasPermission) {
        await _cleanupRecorder();
        if (mounted) {
          _showError(
            Platform.isWindows
                ? 'Microphone access denied. Please enable in Windows Settings > Privacy > Microphone.'
                : Platform.isMacOS
                    ? 'Microphone access denied. Please enable in System Settings > Privacy & Security > Microphone.'
                    : 'Microphone permission is required to record audio.',
          );
        }
        return;
      }

      _logger.info('Starting native recording...');

      // Start recording using native recorder
      final started = await _audioRecorder!.startRecording();

      if (!started) {
        _logger.error('Failed to start native recording', null, null);
        await _cleanupRecorder();
        if (mounted) {
          _showError('Failed to start recording');
        }
        return;
      }

      _logger.info('Recording started successfully');

      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      _logger.error('Failed to start recording', e, null);
      await _cleanupRecorder();

      if (mounted) {
        _showError('Failed to start recording: $e');
      }
    }
  }

  Future<void> _stopRecordingAndExtract() async {
    _logger.info('_stopRecordingAndExtract called');

    // Update UI immediately
    setState(() {
      _isRecording = false;
      _isExtractingTask = true;
    });

    try {
      // Stop the recorder and get the file path
      _logger.info('Stopping native recorder...');

      final path = await _audioRecorder?.stopRecording();
      _logger.info('Native recorder stopped, path: $path');

      // Dispose the recorder
      _audioRecorder?.dispose();
      _audioRecorder = null;

      if (path == null || path.isEmpty) {
        _logger.warning('Recording path is null or empty');
        if (mounted) {
          _showError('Recording failed - no audio captured');
          setState(() => _isExtractingTask = false);
        }
        return;
      }

      _logger.info('Recording stopped, checking file at: $path');

      final audioFile = File(path);

      // Verify file exists
      if (!await audioFile.exists()) {
        _logger.error('Recording file does not exist: $path', null, null);
        if (mounted) {
          _showError('Recording failed - audio file was not created.');
          setState(() => _isExtractingTask = false);
        }
        return;
      }

      // Check file size
      final fileSize = await audioFile.length();
      _logger.info('Recording file size: $fileSize bytes');

      if (fileSize < 100) {
        _logger.error('Recording file too small: $fileSize bytes', null, null);
        if (mounted) {
          _showError('Recording too short. Please record for at least a few seconds.');
          setState(() => _isExtractingTask = false);
        }
        try {
          await audioFile.delete();
        } catch (_) {}
        return;
      }

      // Validate file size (max 20 MB)
      if (fileSize > 20 * 1024 * 1024) {
        if (mounted) {
          _showError('Recording too long. Maximum file size is 20 MB.');
          setState(() => _isExtractingTask = false);
        }
        await audioFile.delete();
        return;
      }

      // Call AI API to extract task
      final extractedTask = await _taskExtractor.extractTaskFromAudio(audioFile);

      // Clean up temp file
      try {
        await audioFile.delete();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _titleController.text = extractedTask.title.toUpperCase();
          _descriptionController.text = extractedTask.description;
          _isExtractingTask = false;
        });
        _showSuccess('Task extracted from voice');
      }
    } catch (e) {
      _logger.error('Error processing audio', e, null);
      if (mounted) {
        setState(() => _isExtractingTask = false);
        _showError('Failed to extract task: $e');
      }
    }
  }

  /// Handle editing an existing task
  Future<void> _handleEditTask(String taskName, String description) async {
    final task = widget.taskToEdit!;

    // Check if task has a reportId
    if (task.reportId == null || task.reportId!.isEmpty) {
      _showError('Cannot edit task: missing report ID');
      setState(() => _isSubmitting = false);
      return;
    }

    // Check if anything changed
    if (taskName == task.taskName && description == task.taskDescription) {
      // No changes, just close
      if (mounted) {
        Navigator.of(context).pop(false);
      }
      return;
    }

    try {
      // Update via API
      final api = ApiService();
      final updatedTaskData = await api.updateTask(
        reportId: task.reportId!,
        taskId: task.id,
        taskName: taskName != task.taskName ? taskName : null,
        taskDescription: description != task.taskDescription ? description : null,
      );

      if (updatedTaskData != null) {
        // Create updated task object
        final updatedTask = task.copyWith(
          taskName: taskName,
          taskDescription: description,
        );

        // Call the callback
        if (widget.onTaskUpdated != null) {
          widget.onTaskUpdated!(updatedTask);
        }

        _logger.info('Task updated: ${task.id}');

        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        throw Exception('Failed to update task');
      }
    } catch (e) {
      _logger.error('Failed to update task', e, null);
      if (mounted) {
        _showError('Failed to update task: $e');
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final attachmentPaths = _attachments
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();

      final taskName = _titleController.text.trim();
      final description = _descriptionController.text.trim();

      // Handle edit mode
      if (widget.isEditMode && widget.taskToEdit != null) {
        await _handleEditTask(taskName, description);
        return;
      }

      // Use unified createTask API for all task creation
      final api = ApiService();
      final result = await api.createTask(
        projectId: widget.projectId,
        taskName: taskName,
        taskDescription: description,
        reportDate: widget.reportDate ?? DateTime.now(),
        attachmentPaths: attachmentPaths,
      );

      if (result == null) {
        throw Exception('Failed to create task');
      }

      _logger.info('Task created for project: ${widget.projectId}');

      // If this is a pending task, mark time entries as submitted
      final isPendingTask = widget.entryIds != null && widget.entryIds!.isNotEmpty;
      if (isPendingTask) {
        await api.markMultipleTimeEntriesSubmitted(widget.entryIds!);
        _logger.info('Time entries marked as submitted');
      }

      // Call the callback with the created task data
      if (widget.onTaskCreated != null) {
        widget.onTaskCreated!(result);
      }

      // Also create a local task for tracking
      try {
        await ref.read(tasksProvider.notifier).createTask(
          projectId: widget.projectId,
          taskName: taskName,
        );
      } catch (e) {
        _logger.warning('Could not create local task: $e');
      }

      if (mounted) {
        Navigator.of(context).pop(true);
      }
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenWidth = MediaQuery.of(context).size.width;
    final isLargeScreen = screenWidth > 500;

    // Always align to bottom for bottom sheet behavior
    // Use Column with Spacer to allow taps on empty area to close the sheet
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // This spacer area allows taps to pass through to close the sheet
        Flexible(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Container(color: Colors.transparent),
          ),
        ),
        // The actual bottom sheet content
        Container(
          margin: EdgeInsets.only(bottom: bottomInset),
          constraints: BoxConstraints(
            maxWidth: isLargeScreen ? 500 : double.infinity,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
            child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Header with mic button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ADD TASK',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.projectName.toUpperCase(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.5),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    // Voice recording button - temporarily hidden (not implemented)
                    // TODO: Uncomment when voice recording is implemented
                    // Material(
                    //   color: Colors.transparent,
                    //   child: InkWell(
                    //     onTap: (_isSubmitting || _isExtractingTask)
                    //         ? null
                    //         : _handleMicTap,
                    //     borderRadius: BorderRadius.circular(8),
                    //     child: MouseRegion(
                    //       cursor: (_isSubmitting || _isExtractingTask)
                    //           ? SystemMouseCursors.forbidden
                    //           : SystemMouseCursors.click,
                    //       child: Container(
                    //         width: 36,
                    //         height: 36,
                    //         decoration: BoxDecoration(
                    //           color: _isExtractingTask
                    //               ? const Color(0xFF374151)
                    //               : _isRecording
                    //                   ? const Color(0xFFDC2626) // Red when recording
                    //                   : const Color(0xFF1E3A5F),
                    //           borderRadius: BorderRadius.circular(8),
                    //         ),
                    //         child: Center(
                    //           child: _isExtractingTask
                    //               ? const SizedBox(
                    //                   width: 16,
                    //                   height: 16,
                    //                   child: CircularProgressIndicator(
                    //                     strokeWidth: 2,
                    //                     valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    //                   ),
                    //                 )
                    //               : Icon(
                    //                   _isRecording ? Icons.stop_rounded : Icons.mic,
                    //                   color: _isRecording
                    //                       ? Colors.white
                    //                       : const Color(0xFF60A5FA),
                    //                   size: 20,
                    //                 ),
                    //         ),
                    //       ),
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
                const SizedBox(height: 24),

                // Task Title
                const Text(
                  'Task Title',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Title here...',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.3),
                      fontSize: 15,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppTheme.primaryColor,
                        width: 2,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Task title is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Description
                const Text(
                  'Description',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Stack(
                  children: [
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Start typing here...',
                        hintStyle: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 15,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF2A2A2A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: AppTheme.primaryColor,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                    // AI sparkle icon - temporarily hidden (not implemented)
                    // TODO: Uncomment when AI enhancement is implemented
                    // Positioned(
                    //   right: 12,
                    //   bottom: 12,
                    //   child: Icon(
                    //     Icons.auto_awesome,
                    //     size: 20,
                    //     color: Colors.amber.withValues(alpha: 0.7),
                    //   ),
                    // ),
                  ],
                ),
                const SizedBox(height: 20),

                // Attachments (only show when adding new task, not when editing)
                if (!widget.isEditMode) ...[
                  const Text(
                    'Attachments',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Attachment previews (only when not in edit mode)
                if (!widget.isEditMode && _attachments.isNotEmpty) ...[
                  SizedBox(
                    height: 70,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _attachments.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 8),
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
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                                color: const Color(0xFF2A2A2A),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(7),
                                child: isImage
                                    ? Image.file(
                                        File(path),
                                        fit: BoxFit.cover,
                                        width: 70,
                                        height: 70,
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.picture_as_pdf,
                                            size: 24,
                                            color: AppTheme.errorColor,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            file.name.length > 8
                                                ? '${file.name.substring(0, 6)}...'
                                                : file.name,
                                            style: const TextStyle(
                                              fontSize: 8,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
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
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // File picker and Screenshot buttons (only when not in edit mode)
                if (!widget.isEditMode && _attachments.length < maxFiles)
                  Row(
                    children: [
                      // File picker button
                      Expanded(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _pickFiles,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF3A5A7C).withValues(alpha: 0.3),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.cloud_upload_outlined,
                                      color: Color(0xFF5B8AB5),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Choose file',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Screenshot button
                      Expanded(
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _takeScreenshot,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2A2A2A),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF7C6AFA).withValues(alpha: 0.3),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.screenshot_outlined,
                                      color: Color(0xFF7C6AFA),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Screenshot',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (!widget.isEditMode && _attachments.length < maxFiles)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'PDF, PNG, JPG (max 5 files, 100MB total)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                SizedBox(height: widget.isEditMode ? 16 : 24),

                // Add Task button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : Text(
                            widget.isEditMode ? 'Save Changes' : 'Add Task',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
        ),
      ],
    );
  }
}
