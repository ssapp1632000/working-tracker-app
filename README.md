# Work Tracker - Flutter Desktop Application

A professional time tracking application built with Flutter for Windows, macOS, and Linux desktop platforms. Features include project time tracking, report generation, and a floating widget for quick access.

## Features

- ✅ **User Authentication** - Login system (mock auth, API-ready)
- ✅ **Project Management** - Track time across multiple projects
- ✅ **Time Tracking** - Start, stop, and switch between project timers
- ✅ **Reports** - View time entries by date range with project breakdown
- ✅ **Floating Widget** - Minimalist floating timer widget (upcoming feature)
- ✅ **Data Persistence** - Local storage using Hive
- ✅ **Clean Architecture** - Well-structured code with separation of concerns
- ✅ **State Management** - Riverpod for reactive state management
- ✅ **Error Handling** - Comprehensive logging and error handling
- ✅ **Modern UI** - Material Design 3 with custom theming

## Architecture

The project follows Clean Architecture principles with clear separation of concerns:

```
lib/
├── core/
│   ├── constants/        # App constants and configuration
│   ├── theme/            # Theme and styling
│   ├── utils/            # Utility functions
│   └── extensions/       # Dart extensions
├── models/               # Data models (User, Project, TimeEntry, Report)
├── services/             # Business logic layer
│   ├── storage_service.dart
│   ├── auth_service.dart
│   ├── project_service.dart
│   ├── timer_service.dart
│   └── logger_service.dart
├── providers/            # Riverpod providers
│   ├── auth_provider.dart
│   ├── project_provider.dart
│   └── timer_provider.dart
├── screens/              # UI screens
│   ├── login_screen.dart
│   ├── dashboard_screen.dart
│   └── report_screen.dart
├── widgets/              # Reusable widgets
│   └── floating_widget.dart
└── main.dart             # App entry point
```

## Prerequisites

### For Development on Mac

1. **Install Homebrew** (if not already installed):
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. **Install Flutter**:
   ```bash
   # Download Flutter SDK
   cd ~/development
   git clone https://github.com/flutter/flutter.git -b stable

   # Add Flutter to PATH (add to ~/.zshrc or ~/.bash_profile)
   export PATH="$PATH:`pwd`/flutter/bin"

   # Reload shell
   source ~/.zshrc
   ```

3. **Verify Installation**:
   ```bash
   flutter doctor
   ```

4. **Enable Desktop Support**:
   ```bash
   flutter config --enable-macos-desktop
   flutter config --enable-windows-desktop
   flutter config --enable-linux-desktop
   ```

## Setup Instructions

### 1. Navigate to Project Directory
```bash
cd /Users/ahmedshaban/Downloads/floating_widget_app
```

### 2. Install Dependencies
```bash
flutter pub get
```

### 3. Generate Hive Adapters
The app uses Hive for local storage. You need to generate the type adapters:

```bash
dart run build_runner build --delete-conflicting-outputs
```

This will generate the following files:
- `lib/models/user.g.dart`
- `lib/models/project.g.dart`
- `lib/models/time_entry.g.dart`
- `lib/models/report.g.dart`

**IMPORTANT**: After generating these files, uncomment the adapter registration lines in `lib/services/storage_service.dart` (lines 27-30):

```dart
Hive.registerAdapter(UserAdapter());
Hive.registerAdapter(ProjectAdapter());
Hive.registerAdapter(TimeEntryAdapter());
Hive.registerAdapter(ReportAdapter());
```

### 4. Run the Application

#### On macOS (for testing):
```bash
flutter run -d macos
```

#### Build for Windows (from Mac):
```bash
flutter build windows --release
```

The Windows executable will be created in:
```
build/windows/x64/runner/Release/
```

Copy the entire `Release` folder to a Windows machine to run the application.

### 5. Run Tests
```bash
flutter test
```

## Running on Windows

Since you're developing on a Mac but need to run on Windows, you have two options:

### Option 1: Build on Mac, Run on Windows
1. Build the Windows executable on Mac (requires setting up Windows toolchain)
2. Copy the `build/windows/x64/runner/Release/` folder to Windows
3. Run `floating_widget_app.exe` on Windows

### Option 2: Use Windows VM or PC
1. Install Flutter on Windows
2. Clone/copy the project
3. Run `flutter pub get`
4. Run `dart run build_runner build`
5. Run `flutter run -d windows`

## How to Use

### Login
1. Launch the application
2. Enter any email address (e.g., `user@example.com`)
3. Enter any password (minimum 6 characters)
4. Click "Login"

**Note**: Currently using mock authentication. Real API integration can be added later.

### Dashboard
- View all available projects
- Click a project to start tracking time
- Click again to stop the timer
- Click a different project to switch timers
- View total time tracked per project

### Reports
- Click the reports icon in the app bar
- Select a date range
- View time breakdown by project
- Export reports (feature coming soon)

## Configuration

### Customize Projects
Edit `lib/core/constants/app_constants.dart`:

```dart
static const List<String> mockProjects = [
  'Your Project 1',
  'Your Project 2',
  'Your Project 3',
];
```

### Customize Theme
Edit `lib/core/theme/app_theme.dart` to change colors, fonts, and styling.

### API Integration (Future)
When ready to integrate with a backend API:

1. Update `lib/core/constants/app_constants.dart` with your API URL:
   ```dart
   static const String apiBaseUrl = 'https://your-api.com';
   ```

2. Implement API calls in:
   - `lib/services/auth_service.dart` (login, register)
   - `lib/services/project_service.dart` (fetch projects)
   - `lib/services/timer_service.dart` (sync time entries)

## Known Issues & TODO

### Current Limitations
- Floating widget feature is implemented but needs window management integration
- Export functionality is not yet implemented
- Keyboard shortcuts are planned but not yet implemented

### Upcoming Features
1. **Floating Widget Integration**
   - Minimize to floating widget functionality
   - Restore main window from floating widget

2. **Export Reports**
   - Export to CSV
   - Export to PDF
   - Export to JSON

3. **Keyboard Shortcuts**
   - Ctrl+Shift+S: Start/Stop timer
   - Ctrl+Shift+R: Open reports
   - Ctrl+Shift+W: Show floating widget

4. **Enhanced Features**
   - Pause/Resume timer
   - Add notes to time entries
   - Edit time entries
   - Delete time entries
   - Project categories
   - Custom project colors

## Troubleshooting

### Error: "Flutter not found"
Make sure Flutter is in your PATH. Run:
```bash
export PATH="$PATH:/path/to/flutter/bin"
```

### Error: "build_runner not generating files"
Try cleaning and rebuilding:
```bash
flutter clean
flutter pub get
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### Error: "Hive adapters not registered"
The Hive adapter registration is commented out in `storage_service.dart` until after running `build_runner`. After generating the `.g.dart` files, uncomment these lines:

```dart
Hive.registerAdapter(UserAdapter());
Hive.registerAdapter(ProjectAdapter());
Hive.registerAdapter(TimeEntryAdapter());
Hive.registerAdapter(ReportAdapter());
```

### Error: "Window manager not working"
Make sure you're running on a desktop platform (Windows, macOS, or Linux), not on mobile or web.

## Contributing

This is a private project, but contributions are welcome. Please follow these guidelines:

1. Follow the existing code structure
2. Write tests for new features
3. Update documentation
4. Use meaningful commit messages

## License

Private project - All rights reserved.

## Support

For issues or questions, please create an issue in the project repository.

---

**Built with ❤️ using Flutter**
