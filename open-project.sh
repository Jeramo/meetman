#!/bin/bash

# Quick launcher script for Meeting Copilot Xcode project

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Opening Meeting Copilot in Xcode...                   ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Navigate to project directory
cd "$(dirname "$0")"

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: Xcode not found"
    echo "   Please install Xcode from the App Store"
    exit 1
fi

# Check if project exists
if [ ! -d "MeetingCopilot.xcodeproj" ]; then
    echo "❌ Error: MeetingCopilot.xcodeproj not found"
    echo "   Current directory: $(pwd)"
    exit 1
fi

echo "✅ Project found: MeetingCopilot.xcodeproj"
echo "✅ Opening in Xcode..."
echo ""

# Open project in Xcode
open MeetingCopilot.xcodeproj

echo "🚀 Xcode should launch now!"
echo ""
echo "Next steps:"
echo "  1. Select iPhone 16 Pro Simulator (or your device)"
echo "  2. Press ⌘R (Cmd+R) to build and run"
echo "  3. Grant permissions when prompted"
echo "  4. Start recording your first meeting!"
echo ""
echo "📚 Documentation: See BUILD_INSTRUCTIONS.md"
echo ""
