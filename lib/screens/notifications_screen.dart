import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../core/theme/app_theme.dart';
import '../providers/notification_provider.dart';
import '../widgets/notification_item.dart';
import '../widgets/window_controls.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isLargeScreen = constraints.maxWidth > 500;
          final horizontalPadding = isLargeScreen ? 32.0 : 16.0;
          final contentMaxWidth = isLargeScreen ? 800.0 : double.infinity;
          final backgroundDecoration = isLargeScreen
              ? AppTheme.fullscreenBackgroundDecoration
              : AppTheme.backgroundDecoration;

          return Container(
            decoration: backgroundDecoration,
            child: Stack(
              children: [
                Column(
                  children: [
                    // Header
                    Container(
                      // decoration: const BoxDecoration(
                      //   color: Color(0xFF1E1E1E),
                      //   border: Border(
                      //     bottom: BorderSide(
                      //       color: Color(0xFF333333),
                      //       width: 1,
                      //     ),
                      //   ),
                      // ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title row - with extra right padding for window controls
                          Padding(
                            padding: EdgeInsets.fromLTRB(horizontalPadding, 40, 0, 16),
                            child: Row(
                              children: [
                                // Back button
                                GestureDetector(
                                  onTap: () => Navigator.of(context).pop(),
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Title
                                const Text(
                                  'NOTIFICATIONS',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const Spacer(),
                                // Refresh button
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: IconButton(
                                    onPressed: () async {
                                      // Clear storage first
                                      await ref.read(notificationProvider.notifier).clearAll();
                                      // Refetch from API
                                      await ref.read(notificationProvider.notifier).fetchNotifications();
                                    },
                                    icon: const Icon(Icons.refresh),
                                    color: Colors.white,
                                    iconSize: 20,
                                    tooltip: 'Refresh notifications',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: contentMaxWidth),
                          child: _buildContent(context, ref, state, horizontalPadding),
                        ),
                      ),
                    ),
                  ],
                ),

                // Top bar with draggable area and window controls
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 40,
                  child: Row(
                    children: [
                      // Draggable area (left side)
                      Expanded(
                        child: GestureDetector(
                          onPanStart: (_) => windowManager.startDragging(),
                          child: Container(
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                      // Window control buttons (minimize, close)
                      const Padding(
                        padding: EdgeInsets.only(
                          top: 8,
                          right: 8,
                        ),
                        child: WindowControls(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    NotificationState state,
    double horizontalPadding,
  ) {
    if (state is NotificationLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppTheme.primaryColor,
        ),
      );
    }

    if (state is NotificationError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              state.message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                ref.read(notificationProvider.notifier).fetchNotifications();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state is NotificationLoaded) {
      if (state.notifications.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 64,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              const Text(
                'No notifications',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        padding: EdgeInsets.symmetric(vertical: 16, horizontal: horizontalPadding),
        itemCount: state.notifications.length,
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          color: Color(0xFF333333),
          indent: 16,
          endIndent: 16,
        ),
        itemBuilder: (context, index) {
          final notification = state.notifications[index];
          return NotificationItem(
            notification: notification,
            onTap: () {
              // No action on tap
            },
          );
        },
      );
    }

    return const SizedBox.shrink();
  }
}
