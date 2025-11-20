# Quick Setup Guide for Work Tracker

This guide is specifically for setting up and running the Work Tracker application when developing on a Mac but targeting Windows.

## Part 1: Install Flutter on Your Mac

### Step 1: Install Homebrew (if not installed)
Open Terminal and run:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Step 2: Create a Development Directory
```bash
mkdir -p ~/development
cd ~/development
```

### Step 3: Download Flutter SDK
```bash
git clone https://github.com/flutter/flutter.git -b stable
```

### Step 4: Add Flutter to Your PATH

For **zsh** (default on recent macOS):
```bash
echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> ~/.zshrc
source ~/.zshrc
```

For **bash**:
```bash
echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> ~/.bash_profile
source ~/.bash_profile
```

### Step 5: Verify Installation
```bash
flutter doctor
```

You should see output showing Flutter installation status. Don't worry about Android Studio or Xcode warnings if you're only targeting desktop.

### Step 6: Enable Desktop Support
```bash
flutter config --enable-macos-desktop
flutter config --enable-windows-desktop
flutter config --enable-linux-desktop
```

## Part 2: Setup the Project

### Step 1: Navigate to Project
```bash
cd /Users/ahmedshaban/Downloads/floating_widget_app
```

### Step 2: Install Dependencies
```bash
flutter pub get
```

This will download all required packages. You should see:
```
Resolving dependencies...
Got dependencies!
```

### Step 3: Generate Hive Type Adapters

The project uses Hive for data storage, which requires code generation:

```bash
dart run build_runner build --delete-conflicting-outputs
```

This will generate 4 files:
- `lib/models/user.g.dart`
- `lib/models/project.g.dart`
- `lib/models/time_entry.g.dart`
- `lib/models/report.g.dart`

### Step 4: Uncomment Hive Adapter Registration

Open `lib/services/storage_service.dart` and find lines 22-26. Uncomment these lines:

```dart
// Before:
// Hive.registerAdapter(UserAdapter());
// Hive.registerAdapter(ProjectAdapter());
// Hive.registerAdapter(TimeEntryAdapter());
// Hive.registerAdapter(ReportAdapter());

// After:
Hive.registerAdapter(UserAdapter());
Hive.registerAdapter(ProjectAdapter());
Hive.registerAdapter(TimeEntryAdapter());
Hive.registerAdapter(ReportAdapter());
```

## Part 3: Running the Application

### Option A: Test on Mac

Run the application on macOS to test functionality:
```bash
flutter run -d macos
```

The app will launch in a new window. You can:
1. Login with any email and password (min 6 chars)
2. See the dashboard with projects
3. Click projects to start/stop timers
4. View reports

### Option B: Build for Windows

To create a Windows executable:

```bash
flutter build windows --release
```

The build output will be in:
```
build/windows/x64/runner/Release/
```

**To run on Windows:**
1. Copy the entire `Release` folder to a USB drive or cloud storage
2. Transfer to your Windows machine
3. Run `floating_widget_app.exe`

## Part 4: Verifying Everything Works

### Check 1: Test Login
1. Run the app
2. Enter email: `test@example.com`
3. Enter password: `password123`
4. Click "Login"
5. Should see the dashboard

### Check 2: Test Timer
1. Click on any project (e.g., "Binghatti Project_1")
2. Timer should start counting
3. Click the project again to stop
4. Check that time is saved

### Check 3: Test Reports
1. Click the reports icon (📊) in the app bar
2. Should see time entries for the current week
3. Try changing the date range

### Check 4: Run Tests
```bash
flutter test
```

All tests should pass ✅

## Common Issues and Solutions

### Issue 1: "flutter: command not found"
**Solution**: Flutter is not in your PATH. Run:
```bash
export PATH="$PATH:$HOME/development/flutter/bin"
```
Then retry.

### Issue 2: "build_runner failed"
**Solution**: Clean and rebuild:
```bash
flutter clean
flutter pub get
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### Issue 3: "Hive adapters not found"
**Solution**: Make sure you:
1. Ran `dart run build_runner build`
2. Uncommented the adapter registration in `storage_service.dart`

### Issue 4: "Unable to build for Windows on Mac"
**Solution**: You have two options:
1. Use a Windows VM on your Mac
2. Transfer the code to a Windows machine and build there

## Project Structure Overview

```
lib/
├── core/                 # Core utilities and constants
│   ├── constants/        # App configuration
│   ├── theme/            # UI theme
│   ├── utils/            # Helper functions
│   └── extensions/       # Dart extensions
├── models/               # Data models
│   ├── user.dart         # User model
│   ├── project.dart      # Project model
│   ├── time_entry.dart   # Time entry model
│   └── report.dart       # Report model
├── services/             # Business logic
│   ├── storage_service.dart  # Local storage
│   ├── auth_service.dart     # Authentication
│   ├── project_service.dart  # Project management
│   ├── timer_service.dart    # Timer logic
│   └── logger_service.dart   # Logging
├── providers/            # Riverpod state management
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

## Customization

### Change Project Names
Edit `lib/core/constants/app_constants.dart`:

```dart
static const List<String> mockProjects = [
  'Your Project 1',
  'Your Project 2',
  'Your Project 3',
];
```

### Change Theme Colors
Edit `lib/core/theme/app_theme.dart`:

```dart
static const Color primaryColor = Color(0xFF2196F3); // Change this
```

### Change App Name
Edit `lib/core/constants/app_constants.dart`:

```dart
static const String appName = 'Your App Name';
```

## Next Steps

Once everything is working:

1. **Customize the projects** - Add your actual project names
2. **Customize the theme** - Match your brand colors
3. **Test thoroughly** - Try all features
4. **Build for Windows** - Create the Windows executable
5. **Deploy** - Install on your Windows machine

## Need Help?

If you run into issues:

1. Check the main README.md for detailed documentation
2. Check the Troubleshooting section
3. Run `flutter doctor` to verify your setup
4. Check the console logs for error messages

## Quick Command Reference

```bash
# Install dependencies
flutter pub get

# Generate code
dart run build_runner build --delete-conflicting-outputs

# Run on Mac
flutter run -d macos

# Build for Windows
flutter build windows --release

# Run tests
flutter test

# Clean project
flutter clean

# Check Flutter installation
flutter doctor
```

## Success Checklist

- ✅ Flutter installed and in PATH
- ✅ Desktop support enabled
- ✅ Dependencies installed (`flutter pub get`)
- ✅ Code generated (`build_runner`)
- ✅ Hive adapters registered
- ✅ App runs on Mac
- ✅ Login works
- ✅ Timers work
- ✅ Reports work
- ✅ Tests pass
- ✅ Windows build created

Once all items are checked, you're ready to go! 🎉
