class AppConstants {
  // App Info
  static const String appName = 'Work Tracker';
  static const String appVersion = '1.0.0';

  // Window Settings
  static const double floatingWidgetWidth = 300.0;
  static const double floatingWidgetHeight = 300.0;
  static const double floatingWidgetCollapsedWidth = 60.0;

  // Timer Settings
  static const int timerUpdateIntervalSeconds = 1;

  // Storage Keys
  static const String hiveBoxUser = 'user_box';
  static const String hiveBoxProjects = 'projects_box';
  static const String hiveBoxTimeEntries = 'time_entries_box';
  static const String hiveBoxReports = 'reports_box';

  // API Endpoints (for future use)
  static const String apiBaseUrl = 'https://api.example.com';
  static const String apiLogin = '/auth/login';
  static const String apiProjects = '/projects';
  static const String apiReports = '/reports';

  // Mock Data - Static Projects (for now)
  static const List<String> mockProjects = [
    'Binghatti Project_1',
    'Binghatti Project_2',
    'Binghatti Project_3',
    'Marina Heights',
    'Downtown Tower',
    'Beach Resort',
  ];

  // Animation Durations
  static const int slideAnimationDuration = 300;
  static const int expandAnimationDuration = 300;

  // Keyboard Shortcuts
  static const String shortcutShowWidget = 'Ctrl+Shift+W';
  static const String shortcutStartTimer = 'Ctrl+Shift+S';
  static const String shortcutPauseTimer = 'Ctrl+Shift+P';
  static const String shortcutGenerateReport = 'Ctrl+Shift+R';
}
