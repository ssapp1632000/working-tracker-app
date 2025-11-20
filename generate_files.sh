#!/bin/bash

# Script to generate Hive adapter files

echo "🔧 Generating Hive adapter files..."
echo ""

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "❌ Flutter is not installed or not in PATH"
    echo ""
    echo "Please install Flutter first:"
    echo "1. Visit https://docs.flutter.dev/get-started/install/macos"
    echo "2. Or follow the instructions in SETUP_GUIDE.md"
    exit 1
fi

echo "✅ Flutter found"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean

# Get dependencies
echo "📦 Getting dependencies..."
flutter pub get

# Generate files
echo "⚙️  Generating Hive adapter files..."
dart run build_runner build --delete-conflicting-outputs

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Generation successful!"
    echo ""
    echo "📝 Next step: Uncomment Hive adapter registration"
    echo "   Open: lib/services/storage_service.dart"
    echo "   Uncomment lines 22-26"
    echo ""
    echo "Then run: flutter run -d macos"
else
    echo ""
    echo "❌ Generation failed"
    echo "Check the errors above"
    exit 1
fi
