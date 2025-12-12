import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_theme.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../widgets/window_controls.dart';

class DailyReportsScreen extends StatefulWidget {
  const DailyReportsScreen({super.key});

  @override
  State<DailyReportsScreen> createState() => _DailyReportsScreenState();
}

class _DailyReportsScreenState extends State<DailyReportsScreen> {
  final _api = ApiService();
  final _logger = LoggerService();
  final _scrollController = ScrollController();

  // Data
  List<Map<String, dynamic>> _reports = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _currentPage = 1;

  // Filters
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _showFilters = false;
  String _activeFilter = 'all'; // all, today, week, month, custom

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadReports();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMoreReports();
    }
  }

  Future<void> _loadReports({bool refresh = false}) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _currentPage = 1;
        _reports = [];
        _hasMore = true;
      }
    });

    try {
      final result = await _api.getDailyReports(
        page: _currentPage,
        limit: 20,
        from: _fromDate,
        to: _toDate,
      );

      final reports = (result['reports'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      final meta = result['meta'] as Map<String, dynamic>;

      setState(() {
        _reports = reports;
        _hasMore = _currentPage < (meta['totalPages'] ?? 1);
        _isLoading = false;
      });
    } catch (e) {
      _logger.error('Failed to load reports', e, null);
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreReports() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final result = await _api.getDailyReports(
        page: nextPage,
        limit: 20,
        from: _fromDate,
        to: _toDate,
      );

      final reports = (result['reports'] as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      final meta = result['meta'] as Map<String, dynamic>;

      setState(() {
        _reports.addAll(reports);
        _currentPage = nextPage;
        _hasMore = nextPage < (meta['totalPages'] ?? 1);
        _isLoadingMore = false;
      });
    } catch (e) {
      _logger.error('Failed to load more reports', e, null);
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  void _applyFilter(String filter) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _activeFilter = filter;
      switch (filter) {
        case 'today':
          _fromDate = today;
          _toDate = today.add(const Duration(days: 1));
          break;
        case 'week':
          _fromDate = today.subtract(Duration(days: today.weekday - 1));
          _toDate = now;
          break;
        case 'month':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = now;
          break;
        case 'all':
          _fromDate = null;
          _toDate = null;
          break;
        case 'custom':
          // Keep current dates, just mark as custom
          break;
      }
    });

    _loadReports(refresh: true);
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : DateTimeRange(
              start: DateTime.now().subtract(const Duration(days: 7)),
              end: DateTime.now(),
            ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primaryColor,
              onPrimary: Colors.white,
              surface: AppTheme.surfaceColor,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _fromDate = picked.start;
        _toDate = picked.end.add(const Duration(days: 1));
        _activeFilter = 'custom';
      });
      _loadReports(refresh: true);
    }
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return '';
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('EEE, MMM d, yyyy').format(date);
    } catch (e) {
      return isoDate;
    }
  }

  String _formatDateShort(DateTime date) {
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Stack(
        children: [
          Column(
            children: [
              // Custom Header with gradient
              Container(
                padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
                decoration: const BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                ),
                child: Row(
                  children: [
                    // Back button
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Back',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    // Title
                    const Expanded(
                      child: Text(
                        'My Reports',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    // Filter toggle button
                    IconButton(
                      icon: Icon(
                        _showFilters ? Icons.filter_list_off : Icons.filter_list,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() {
                          _showFilters = !_showFilters;
                        });
                      },
                      tooltip: 'Toggle Filters',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Filter Section
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: _showFilters ? null : 0,
                child: _showFilters ? _buildFilterSection() : const SizedBox.shrink(),
              ),

              // Content
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
          // Window controls (minimize, close)
          const Positioned(
            top: 8,
            right: 8,
            child: WindowControls(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', 'all'),
                const SizedBox(width: 8),
                _buildFilterChip('Today', 'today'),
                const SizedBox(width: 8),
                _buildFilterChip('This Week', 'week'),
                const SizedBox(width: 8),
                _buildFilterChip('This Month', 'month'),
                const SizedBox(width: 8),
                _buildDateRangeButton(),
              ],
            ),
          ),

          // Show selected date range
          if (_fromDate != null || _toDate != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.date_range,
                    size: 16,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fromDate != null && _toDate != null
                        ? '${_formatDateShort(_fromDate!)} - ${_formatDateShort(_toDate!.subtract(const Duration(days: 1)))}'
                        : 'All time',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  if (_activeFilter != 'all') ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _applyFilter('all'),
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String filter) {
    final isActive = _activeFilter == filter;
    return GestureDetector(
      onTap: () => _applyFilter(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryColor : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppTheme.primaryColor : AppTheme.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDateRangeButton() {
    final isActive = _activeFilter == 'custom';
    return GestureDetector(
      onTap: _selectDateRange,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryColor : AppTheme.backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppTheme.primaryColor : AppTheme.borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today,
              size: 14,
              color: isActive ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'Custom',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _reports.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppTheme.primaryColor,
        ),
      );
    }

    if (_error != null && _reports.isEmpty) {
      return _buildErrorState();
    }

    if (_reports.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadReports(refresh: true),
      color: AppTheme.primaryColor,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(12),
        itemCount: _reports.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _reports.length) {
            return _buildLoadingMore();
          }
          return _buildReportCard(_reports[index]);
        },
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppTheme.errorColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load reports',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadReports(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.description_outlined,
            size: 64,
            color: AppTheme.textHint,
          ),
          const SizedBox(height: 16),
          Text(
            'No reports found',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _activeFilter != 'all'
                ? 'Try adjusting your date filters'
                : 'Submit your first daily report to see it here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingMore() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _isLoadingMore
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryColor,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final reportDate = report['reportDate'] as String?;
    final tasks = (report['tasks'] as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];
    final orientation = report['orientation'] as String? ?? 'l';
    final taskCount = report['taskCount'] ?? tasks.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 18,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _formatDate(reportDate),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.task_alt,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$taskCount task${taskCount != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    orientation.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tasks List
          if (tasks.isNotEmpty)
            ...tasks.asMap().entries.map((entry) {
              final index = entry.key;
              final task = entry.value;
              final isLast = index == tasks.length - 1;
              return _buildTaskItem(task, isLast);
            }),

          if (tasks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No tasks in this report',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskItem(Map<String, dynamic> task, bool isLast) {
    final project = task['project'] as Map<String, dynamic>?;
    final projectName = project?['name'] ?? 'Unknown Project';
    final title = task['title'] ?? '';
    final description = task['description'] ?? '';
    final images = (task['images'] as List?)
            ?.map((e) => e as Map<String, dynamic>)
            .toList() ??
        [];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: AppTheme.borderColor,
                  width: 1,
                ),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Project & Title
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  projectName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Description
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Attachments
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 60,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: images.length,
                itemBuilder: (context, index) {
                  final image = images[index];
                  final imageUrl = image['path'] as String? ?? '';
                  return GestureDetector(
                    onTap: () => _showImagePreview(imageUrl),
                    child: Container(
                      width: 60,
                      height: 60,
                      margin: EdgeInsets.only(right: index < images.length - 1 ? 8 : 0),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.borderColor),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppTheme.backgroundColor,
                              child: Icon(
                                Icons.image_not_supported,
                                size: 24,
                                color: AppTheme.textHint,
                              ),
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: AppTheme.backgroundColor,
                              child: const Center(
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showImagePreview(String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.broken_image,
                              size: 48,
                              color: AppTheme.textHint,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Failed to load image',
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
