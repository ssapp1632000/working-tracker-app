import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class InlineTaskEntry extends StatefulWidget {
  final String projectId;
  final bool isCompact;
  final Function(String taskName) onSubmit;

  const InlineTaskEntry({
    super.key,
    required this.projectId,
    required this.onSubmit,
    this.isCompact = false,
  });

  @override
  State<InlineTaskEntry> createState() => _InlineTaskEntryState();
}

class _InlineTaskEntryState extends State<InlineTaskEntry> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final taskName = _controller.text.trim();
    if (taskName.isNotEmpty) {
      widget.onSubmit(taskName);
      _controller.clear();
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.isCompact ? 36.0 : 40.0;
    final fontSize = widget.isCompact ? 12.0 : 13.0;
    final iconSize = widget.isCompact ? 18.0 : 20.0;
    final horizontalPadding = widget.isCompact ? 8.0 : 12.0;
    final verticalPadding = widget.isCompact ? 6.0 : 8.0;

    return Container(
      height: height,
      margin: const EdgeInsets.only(
        top: 4,
        bottom: 4,
      ),
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
                hintText: 'Enter task name...',
                hintStyle: TextStyle(
                  color: AppTheme.textHint,
                  fontSize: fontSize,
                ),
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
                  vertical: verticalPadding,
                ),
                isDense: true,
                filled: true,
                fillColor: AppTheme.surfaceColor,
              ),
              onSubmitted: (_) => _handleSubmit(),
            ),
          ),
          SizedBox(width: widget.isCompact ? 4 : 8),
          InkWell(
            onTap: _handleSubmit,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppTheme.successColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.check,
                size: iconSize,
                color: AppTheme.successColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
