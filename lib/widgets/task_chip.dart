import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/task.dart';

class TaskChip extends StatefulWidget {
  final Task task;
  final int index;
  final bool isCompact;
  final Function(String newName)? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onActivate;
  final bool isActive;
  final Duration? currentDuration;

  const TaskChip({
    super.key,
    required this.task,
    required this.index,
    this.isCompact = false,
    this.onEdit,
    this.onDelete,
    this.onActivate,
    this.isActive = false,
    this.currentDuration,
  });

  @override
  State<TaskChip> createState() => _TaskChipState();
}

class _TaskChipState extends State<TaskChip> {
  bool _isEditing = false;
  bool _isHovered = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.taskName);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
      _controller.text = widget.task.taskName;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _controller.text = widget.task.taskName;
    });
  }

  void _submitEdit() {
    final newName = _controller.text.trim();
    if (newName.isNotEmpty && newName != widget.task.taskName) {
      widget.onEdit?.call(newName);
    }
    setState(() {
      _isEditing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.isCompact ? 32.0 : 36.0;
    final editHeight = widget.isCompact ? 36.0 : 40.0;
    final fontSize = widget.isCompact ? 11.0 : 12.0;
    final iconSize = widget.isCompact ? 14.0 : 16.0;
    final horizontalPadding = widget.isCompact ? 8.0 : 12.0;

    if (_isEditing) {
      return Container(
        height: editHeight,
        margin: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: TextStyle(
                  fontSize: fontSize,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(
                      color: AppTheme.primaryColor,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: widget.isCompact ? 6.0 : 8.0,
                  ),
                  isDense: true,
                  filled: true,
                  fillColor: AppTheme.surfaceColor,
                ),
                onSubmitted: (_) => _submitEdit(),
              ),
            ),
            SizedBox(width: widget.isCompact ? 4 : 8),
            // Save button
            InkWell(
              onTap: _submitEdit,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppTheme.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  Icons.check,
                  size: widget.isCompact ? 18.0 : 20.0,
                  color: AppTheme.successColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Cancel button
            InkWell(
              onTap: _cancelEditing,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: widget.isCompact ? 18.0 : 20.0,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Calculate widths for hover animation
    // Don't animate when active
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final activateButtonWidth = widget.isCompact ? 60.0 : 70.0;
        // Don't shrink when active
        final shouldAnimate = _isHovered && !widget.isActive;
        final chipWidth = shouldAnimate ? totalWidth * 0.7 : totalWidth;
        final buttonVisibleWidth = shouldAnimate ? activateButtonWidth : 0.0;

        return MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                // Task chip with animation
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: chipWidth,
                  height: height,
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: EdgeInsets.only(
                    left: horizontalPadding,
                    right: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isActive
                        ? AppTheme.successColor.withValues(alpha: 0.15)
                        : AppTheme.backgroundColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.isActive
                          ? AppTheme.successColor.withValues(alpha: 0.4)
                          : AppTheme.borderColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Green indicator dot when active (on the left)
                      if (widget.isActive)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(
                            color: AppTheme.successColor,
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        Text(
                          '${widget.index}-',
                          style: TextStyle(
                            fontSize: fontSize,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (!widget.isActive) SizedBox(width: widget.isCompact ? 6 : 8),
                      // Task name
                      Expanded(
                        child: Text(
                          widget.task.taskName,
                          style: TextStyle(
                            fontSize: fontSize,
                            color: widget.isActive
                                ? AppTheme.successColor
                                : AppTheme.textPrimary,
                            fontWeight: widget.isActive
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Edit button (hide when active to save space)
                      if (widget.onEdit != null && !widget.isActive)
                        InkWell(
                          onTap: _startEditing,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.edit_outlined,
                              size: iconSize,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      // Delete button (hide when active to save space)
                      if (widget.onDelete != null && !widget.isActive)
                        InkWell(
                          onTap: widget.onDelete,
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: iconSize,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Activate button (slides in from right) - only show when not active
                if (widget.onActivate != null && !widget.isActive)
                  ClipRect(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: buttonVisibleWidth,
                      height: height - 4, // Account for margin
                      child: OverflowBox(
                        maxWidth: activateButtonWidth,
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: InkWell(
                            onTap: widget.onActivate,
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: activateButtonWidth - 6,
                              height: height - 4,
                              decoration: BoxDecoration(
                                color: AppTheme.successColor,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Text(
                                  'Start',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: widget.isCompact ? 10.0 : 11.0,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
