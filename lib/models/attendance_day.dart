import 'package:intl/intl.dart';

import 'attendance_period.dart';

/// Justification for an attendance day (for late arrivals, etc.)
class AttendanceJustification {
  final String? content;
  final String? attachmentUrl;

  AttendanceJustification({
    this.content,
    this.attachmentUrl,
  });

  factory AttendanceJustification.fromJson(Map<String, dynamic> json) {
    return AttendanceJustification(
      content: json['content']?.toString(),
      attachmentUrl: json['attachmentUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (content != null) 'content': content,
      if (attachmentUrl != null) 'attachmentUrl': attachmentUrl,
    };
  }
}

/// Represents an attendance day record from the API
class AttendanceDay {
  final String id;
  final String userId;
  final DateTime day;
  final List<DateTime> intervals;
  final double totalSeconds;
  final AttendanceJustification? justification;
  final List<AttendancePeriod>? periods;
  final bool? isActiveFromApi;

  AttendanceDay({
    required this.id,
    required this.userId,
    required this.day,
    required this.intervals,
    this.totalSeconds = 0,
    this.justification,
    this.periods,
    this.isActiveFromApi,
  });

  // Computed properties
  /// Whether user has checked in at least once today
  bool get hasCheckedIn {
    if (intervals.isNotEmpty) return true;
    if (periods != null && periods!.isNotEmpty) return true;
    return false;
  }

  /// Whether user is currently checked out (even number of intervals means last action was checkout)
  /// Odd intervals = currently checked in, Even intervals = currently checked out
  bool get hasCheckedOut {
    // Check periods first (new API format)
    if (periods != null && periods!.isNotEmpty) {
      return periods!.last.endTime != null;
    }
    // Fallback to intervals (old API format)
    return intervals.isNotEmpty && intervals.length.isEven;
  }

  /// Whether user is currently in an active work session (checked in but not checked out)
  bool get isCurrentlyCheckedIn {
    // Use isActiveFromApi if available (from /attendance/status API)
    if (isActiveFromApi != null) return isActiveFromApi!;
    // Check periods (new API format)
    if (periods != null && periods!.isNotEmpty) {
      return periods!.last.endTime == null;
    }
    // Fallback to intervals (old API format)
    return intervals.isNotEmpty && intervals.length.isOdd;
  }

  /// Get the first check-in time of the day
  DateTime? get checkInTime {
    // Check periods first (new API format)
    if (periods != null && periods!.isNotEmpty) {
      return periods!.first.startTime;
    }
    // Fallback to intervals (old API format)
    return intervals.isNotEmpty ? intervals[0] : null;
  }

  /// Get the last check-out time (or null if still checked in)
  DateTime? get checkOutTime {
    // Check periods first (new API format)
    if (periods != null && periods!.isNotEmpty) {
      final lastPeriod = periods!.last;
      return lastPeriod.endTime;
    }
    // Fallback to intervals (old API format)
    return intervals.length > 1 && intervals.length.isEven ? intervals.last : null;
  }

  /// Get the most recent check-in time (last odd-indexed interval)
  DateTime? get lastCheckInTime {
    // Check periods first (new API format)
    if (periods != null && periods!.isNotEmpty) {
      return periods!.last.startTime;
    }
    // Fallback to intervals (old API format)
    if (intervals.isEmpty) return null;
    // If odd number of intervals, last one is check-in
    // If even number, second-to-last is check-in
    final idx = intervals.length.isOdd ? intervals.length - 1 : intervals.length - 2;
    return idx >= 0 ? intervals[idx] : null;
  }

  String get formattedCheckIn => checkInTime != null
      ? DateFormat('h:mm a').format(checkInTime!.toLocal())
      : '--';

  String get formattedCheckOut => checkOutTime != null
      ? DateFormat('h:mm a').format(checkOutTime!.toLocal())
      : '--';

  /// Total time as Duration
  Duration get totalDuration => Duration(seconds: totalSeconds.toInt());

  /// Formatted total time (e.g., "8h 30m")
  String get formattedTotalTime {
    final hours = totalDuration.inHours;
    final minutes = totalDuration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }

  /// Get the current active period (if user is checked in)
  AttendancePeriod? get currentPeriod {
    if (periods != null && periods!.isNotEmpty) {
      final lastPeriod = periods!.last;
      if (lastPeriod.isActive) return lastPeriod;
    }
    return null;
  }

  /// Live total duration including elapsed time from active period
  Duration get liveTotalDuration {
    // For live counter updates, we calculate elapsed time from the current period start
    // and add it to any completed periods' time

    if (isCurrentlyCheckedIn && currentPeriod != null) {
      // Calculate live elapsed from current period start
      final liveElapsed = DateTime.now().difference(currentPeriod!.startTime);

      // Calculate time from completed periods (all periods except current)
      Duration completedTime = Duration.zero;
      if (periods != null && periods!.length > 1) {
        for (int i = 0; i < periods!.length - 1; i++) {
          completedTime += periods![i].duration;
        }
      }

      return completedTime + liveElapsed;
    } else if (isCurrentlyCheckedIn && lastCheckInTime != null && periods == null) {
      // Fallback to intervals if periods not available (old API format)
      Duration total = Duration(seconds: totalSeconds.toInt());
      final elapsed = DateTime.now().difference(lastCheckInTime!);
      return total + elapsed;
    }

    // Not currently checked in - return the total from API
    return Duration(seconds: totalSeconds.toInt());
  }

  /// Formatted live total time with seconds (e.g., "5h 32m 15s")
  String get formattedLiveTotalTime {
    final duration = liveTotalDuration;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    }
    return '${seconds}s';
  }

  factory AttendanceDay.fromJson(Map<String, dynamic> json) {
    // Parse intervals
    final intervalsJson = json['intervals'] as List<dynamic>? ?? [];
    final intervals = intervalsJson.map((e) {
      if (e is DateTime) return e;
      return DateTime.parse(e.toString()).toLocal();
    }).toList();

    // Parse justification if present
    AttendanceJustification? justification;
    if (json['justification'] != null && json['justification'] is Map) {
      justification = AttendanceJustification.fromJson(
        json['justification'] as Map<String, dynamic>,
      );
    }

    // Parse periods if present (from /attendance/status API)
    List<AttendancePeriod>? periods;
    if (json['periods'] != null && json['periods'] is List) {
      periods = (json['periods'] as List)
          .map((p) => AttendancePeriod.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    return AttendanceDay(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      userId: json['user']?.toString() ?? '',
      day: json['day'] is DateTime
          ? json['day']
          : DateTime.parse(json['day'].toString()).toLocal(),
      intervals: intervals,
      totalSeconds: (json['totalSeconds'] as num?)?.toDouble() ?? 0,
      justification: justification,
      periods: periods,
      isActiveFromApi: json['isActive'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'user': userId,
      'day': day.toIso8601String(),
      'intervals': intervals.map((e) => e.toIso8601String()).toList(),
      'totalSeconds': totalSeconds,
      if (justification != null) 'justification': justification!.toJson(),
      if (periods != null) 'periods': periods!.map((p) => p.toJson()).toList(),
      if (isActiveFromApi != null) 'isActive': isActiveFromApi,
    };
  }

  AttendanceDay copyWith({
    String? id,
    String? userId,
    DateTime? day,
    List<DateTime>? intervals,
    double? totalSeconds,
    AttendanceJustification? justification,
    List<AttendancePeriod>? periods,
    bool? isActiveFromApi,
  }) {
    return AttendanceDay(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      day: day ?? this.day,
      intervals: intervals ?? this.intervals,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      justification: justification ?? this.justification,
      periods: periods ?? this.periods,
      isActiveFromApi: isActiveFromApi ?? this.isActiveFromApi,
    );
  }

  @override
  String toString() {
    return 'AttendanceDay(id: $id, day: $day, intervals: ${intervals.length}, totalSeconds: $totalSeconds)';
  }
}
