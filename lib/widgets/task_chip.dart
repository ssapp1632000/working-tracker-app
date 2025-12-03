import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/task.dart';

class TaskChip extends StatefulWidget {
  final Task task;
  final bool isCompact;
  final Function(String newName)? onEdit;
  final VoidCallback? onDelete;

  const TaskChip({
    super.key,
    required this.task,
    this.isCompact = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<TaskChip> createState() => _TaskChipState();
}

class _TaskChipState extends State<TaskChip> {
  bool _isEditing = false;
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

    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 4),
      padding: EdgeInsets.only(
        left: horizontalPadding,
        right: 4,
      ),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: iconSize,
            color: AppTheme.primaryColor.withValues(alpha: 0.6),
          ),
          SizedBox(width: widget.isCompact ? 6 : 8),
          Expanded(
            child: Text(
              widget.task.taskName,
              style: TextStyle(
                fontSize: fontSize,
                color: AppTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Edit button
          if (widget.onEdit != null)
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
          // Delete button
          if (widget.onDelete != null)
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
    );
  }
}
