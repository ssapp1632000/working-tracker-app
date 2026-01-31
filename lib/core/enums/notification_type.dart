import 'package:flutter/material.dart';

enum NotificationType {
  // News & Announcements
  NEWS_POSTED,

  // Employee Recognition
  WELCOME_MESSAGE,
  HAPPY_BIRTHDAY,
  EMPLOYEE_OF_THE_MONTH,
  CONGRATULATE_EMPLOYEE_OF_THE_MONTH,
  EOTM_REMINDER,

  // Golden Buzz
  GOLDEN_BUZZ_ANNOUNCEMENT,
  GOLDEN_BUZZ_CONGRATULATION,

  // Competitions
  COMPETITION_CREATED,
  COMPETITION_TEAM_CREATED,
  COMPETITION_VOTE_ENDED,
  COMPETITION_PHASE_CHANGED,

  // Projects
  PROJECT_CREATED,

  // Team Management
  TEAM_EVALUATION_REMINDER,
  NEW_EMPLOYEE_ASSIGNED,
  EVALUATION_RECEIVED,

  // Requests & Approvals
  REQUEST_APPROVAL,
  REQUEST_DECISION,

  // Bug Tracking
  BUG_SUBMITTED,

  // Attendance
  STILL_WORKING,
  AUTO_CHECKOUT,
  MIDNIGHT_STILL_WORKING,
  NOON_STILL_WORKING,
}

extension NotificationTypeExtension on NotificationType {
  String get value => name;

  static NotificationType? fromString(String value) {
    try {
      return NotificationType.values.firstWhere((e) => e.name == value);
    } catch (_) {
      return null;
    }
  }

  // Get icon for notification type
  IconData get icon {
    switch (this) {
      case NotificationType.NEWS_POSTED:
        return Icons.article;
      case NotificationType.GOLDEN_BUZZ_ANNOUNCEMENT:
      case NotificationType.GOLDEN_BUZZ_CONGRATULATION:
        return Icons.star;
      case NotificationType.HAPPY_BIRTHDAY:
        return Icons.cake;
      case NotificationType.REQUEST_APPROVAL:
      case NotificationType.REQUEST_DECISION:
        return Icons.assignment;
      case NotificationType.EVALUATION_RECEIVED:
        return Icons.rate_review;
      case NotificationType.COMPETITION_CREATED:
      case NotificationType.COMPETITION_PHASE_CHANGED:
        return Icons.emoji_events;
      case NotificationType.AUTO_CHECKOUT:
      case NotificationType.STILL_WORKING:
        return Icons.access_time;
      default:
        return Icons.notifications;
    }
  }

  // Get color for notification type
  Color get color {
    switch (this) {
      case NotificationType.NEWS_POSTED:
        return Colors.blue;
      case NotificationType.GOLDEN_BUZZ_ANNOUNCEMENT:
      case NotificationType.GOLDEN_BUZZ_CONGRATULATION:
        return Colors.amber;
      case NotificationType.HAPPY_BIRTHDAY:
        return Colors.pink;
      case NotificationType.REQUEST_APPROVAL:
      case NotificationType.REQUEST_DECISION:
        return Colors.orange;
      case NotificationType.EVALUATION_RECEIVED:
        return Colors.purple;
      case NotificationType.COMPETITION_CREATED:
      case NotificationType.COMPETITION_PHASE_CHANGED:
        return Colors.green;
      case NotificationType.AUTO_CHECKOUT:
      case NotificationType.STILL_WORKING:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
