import 'package:flutter_test/flutter_test.dart';
import 'package:floating_widget_app/models/project.dart';
import 'package:floating_widget_app/models/time_entry.dart';

void main() {
  group('TimeEntry Tests', () {
    test('TimeEntry should calculate actual duration correctly', () {
      final startTime = DateTime.now().subtract(const Duration(minutes: 5));
      final entry = TimeEntry(
        id: 'test_1',
        projectId: 'proj_1',
        projectName: 'Test Project',
        startTime: startTime,
        isRunning: true,
      );

      // The actual duration should be approximately 5 minutes
      final duration = entry.actualDuration;
      expect(duration.inMinutes, greaterThanOrEqualTo(4));
      expect(duration.inMinutes, lessThanOrEqualTo(6));
    });

    test('TimeEntry should use stored duration when not running', () {
      final startTime = DateTime.now().subtract(const Duration(hours: 2));
      final endTime = DateTime.now().subtract(const Duration(hours: 1));
      final storedDuration = const Duration(hours: 1);

      final entry = TimeEntry(
        id: 'test_2',
        projectId: 'proj_1',
        projectName: 'Test Project',
        startTime: startTime,
        endTime: endTime,
        duration: storedDuration,
        isRunning: false,
      );

      expect(entry.actualDuration, equals(storedDuration));
    });

    test('TimeEntry copyWith should update fields correctly', () {
      final entry = TimeEntry(
        id: 'test_3',
        projectId: 'proj_1',
        projectName: 'Test Project',
        startTime: DateTime.now(),
        isRunning: true,
      );

      final updatedEntry = entry.copyWith(
        isRunning: false,
        duration: const Duration(minutes: 30),
      );

      expect(updatedEntry.isRunning, false);
      expect(updatedEntry.duration, equals(const Duration(minutes: 30)));
      expect(updatedEntry.id, equals(entry.id));
    });

    test('TimeEntry toJson and fromJson should work correctly', () {
      final entry = TimeEntry(
        id: 'test_4',
        projectId: 'proj_1',
        projectName: 'Test Project',
        startTime: DateTime.now(),
        duration: const Duration(hours: 2, minutes: 30),
        description: 'Test description',
        isRunning: false,
      );

      final json = entry.toJson();
      final recreatedEntry = TimeEntry.fromJson(json);

      expect(recreatedEntry.id, equals(entry.id));
      expect(recreatedEntry.projectId, equals(entry.projectId));
      expect(recreatedEntry.projectName, equals(entry.projectName));
      expect(recreatedEntry.duration.inSeconds, equals(entry.duration.inSeconds));
      expect(recreatedEntry.description, equals(entry.description));
      expect(recreatedEntry.isRunning, equals(entry.isRunning));
    });
  });

  group('Project Tests', () {
    test('Project should initialize with correct defaults', () {
      final project = Project(
        id: 'proj_1',
        name: 'Test Project',
        createdAt: DateTime.now(),
      );

      expect(project.status, equals('active'));
      expect(project.totalTime, equals(Duration.zero));
    });

    test('Project copyWith should update total time', () {
      final project = Project(
        id: 'proj_1',
        name: 'Test Project',
        createdAt: DateTime.now(),
      );

      final updatedProject = project.copyWith(
        totalTime: const Duration(hours: 5),
      );

      expect(updatedProject.totalTime, equals(const Duration(hours: 5)));
      expect(updatedProject.name, equals(project.name));
    });

    test('Project toJson and fromJson should preserve data', () {
      final project = Project(
        id: 'proj_1',
        name: 'Test Project',
        description: 'A test project',
        client: 'Test Client',
        createdAt: DateTime.now(),
        deadline: DateTime.now().add(const Duration(days: 30)),
        status: 'active',
        totalTime: const Duration(hours: 10, minutes: 30),
      );

      final json = project.toJson();
      final recreatedProject = Project.fromJson(json);

      expect(recreatedProject.id, equals(project.id));
      expect(recreatedProject.name, equals(project.name));
      expect(recreatedProject.description, equals(project.description));
      expect(recreatedProject.client, equals(project.client));
      expect(recreatedProject.status, equals(project.status));
      expect(recreatedProject.totalTime.inSeconds, equals(project.totalTime.inSeconds));
    });
  });

  group('Duration Formatting Tests', () {
    test('Duration should format correctly', () {
      // Helper function to format duration
      String formatDuration(Duration duration) {
        String twoDigits(int n) => n.toString().padLeft(2, '0');
        final hours = twoDigits(duration.inHours);
        final minutes = twoDigits(duration.inMinutes.remainder(60));
        final seconds = twoDigits(duration.inSeconds.remainder(60));
        return '$hours:$minutes:$seconds';
      }

      expect(formatDuration(const Duration(hours: 1, minutes: 30, seconds: 45)), '01:30:45');
      expect(formatDuration(const Duration(hours: 0, minutes: 5, seconds: 0)), '00:05:00');
      expect(formatDuration(const Duration(hours: 10, minutes: 0, seconds: 1)), '10:00:01');
    });
  });
}
