# Quick Fix - Build Errors

You're seeing errors because the Hive adapter files haven't been generated yet. Here's how to fix it:

## ✅ The Issue

The error messages show:
```
Error: Error when reading 'lib/models/user.g.dart': No such file or directory
```

This means the generated files don't exist yet. We need to create them using `build_runner`.

## 🔧 Solution (Choose One)

### Option 1: Automatic (Recommended)

Run the helper script I created:

```bash
cd /Users/ahmedshaban/Downloads/floating_widget_app
./generate_files.sh
```

This will:
1. Clean the project
2. Install dependencies
3. Generate the missing files

### Option 2: Manual

Run these commands one by one:

```bash
cd /Users/ahmedshaban/Downloads/floating_widget_app

# Clean the project
flutter clean

# Get dependencies
flutter pub get

# Generate Hive adapter files
dart run build_runner build --delete-conflicting-outputs
```

## ✅ After Generation

Once the files are generated, you need to **uncomment** the adapter registration:

1. Open: [lib/services/storage_service.dart](lib/services/storage_service.dart)
2. Find lines 22-26 (around line 22)
3. Remove the `//` comments from these lines:

**Before:**
```dart
// Hive.registerAdapter(UserAdapter());
// Hive.registerAdapter(ProjectAdapter());
// Hive.registerAdapter(TimeEntryAdapter());
// Hive.registerAdapter(ReportAdapter());
```

**After:**
```dart
Hive.registerAdapter(UserAdapter());
Hive.registerAdapter(ProjectAdapter());
Hive.registerAdapter(TimeEntryAdapter());
Hive.registerAdapter(ReportAdapter());
```

## 🚀 Then Run

```bash
flutter run -d macos
```

## 📝 What Just Happened?

1. **build_runner** generated 4 files:
   - `lib/models/user.g.dart`
   - `lib/models/project.g.dart`
   - `lib/models/time_entry.g.dart`
   - `lib/models/report.g.dart`

2. These files contain the code that tells Hive how to store/retrieve our data

3. We uncommented the registration code so the app knows to use these adapters

## ❓ Still Having Issues?

### Error: "flutter: command not found"

Flutter isn't in your PATH. Add it:

```bash
export PATH="$PATH:$HOME/Developer/flutter/bin"
```

Then try again.

### Error: "build_runner fails"

Try this:

```bash
flutter clean
rm -rf ~/.pub-cache
flutter pub get
dart run build_runner build --delete-conflicting-outputs
```

### Can't find Flutter installation

Check where Flutter is installed:

```bash
which flutter
```

If nothing shows up, Flutter isn't installed. Follow the installation guide in SETUP_GUIDE.md.

## ✅ Success Checklist

- [ ] Ran `flutter pub get`
- [ ] Ran `dart run build_runner build`
- [ ] Generated files exist in `lib/models/*.g.dart`
- [ ] Uncommented adapter registration in `storage_service.dart`
- [ ] App runs with `flutter run -d macos`

Once all checked, you're good to go! 🎉
