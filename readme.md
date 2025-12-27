<div align="center">

# MonkeyNote

<img src="MonkeyNote/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" alt="MonkeyNote Icon" width="200"/>

### A Modern Note-Taking Application for macOS

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2015.7+-lightgrey.svg)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

</div>

## Overview

MonkeyNote is a minimalist, native macOS note-taking application built with SwiftUI. It provides a clean, distraction-free interface for organizing your thoughts with powerful features like markdown rendering, custom cursor controls, intelligent autocomplete, and hierarchical folder organization.

## ✨ Features

- **Hierarchical Organization**: Create unlimited nested folders to organize your notes
- **Markdown Rendering**: Real-time markdown syntax highlighting and rendering
- **Custom Cursor**: Configurable cursor width, blinking, and animation settings
- **Smart Autocomplete**: Intelligent word and line completion with customizable delay
- **Powerful Search**: Fast in-document search with match navigation
- **Dark/Light Mode**: Beautiful native themes optimized for both modes
- **Drag & Drop**: Intuitive drag-and-drop support for notes and folders
- **Auto-Save**: Automatic note saving with delayed persistence (10 seconds)
- **Trash Management**: Built-in trash system with restore functionality
- **Statistics Tracking**: Real-time word, line, and character count
- **Font Customization**: Choose from monospaced, rounded, or serif fonts
- **Note Preview**: Quick preview of note content in the list view
- **Keyboard Shortcuts**: Efficient keyboard navigation (⌘F for search)

## 📋 Requirements

- macOS 15.7 or later
- Xcode 16.2 or later (for building from source)

## 🚀 Installation

### Download Pre-built App

1. Download the latest `MonkeyNote.dmg` from the [Releases](https://github.com/yourusername/MonkeyNote/releases) page
2. Open the DMG file
3. Drag **MonkeyNote** to your **Applications** folder
4. Launch MonkeyNote from Applications

> **Note**: If macOS shows "app cannot be opened", go to **System Settings > Privacy & Security** and click **Open Anyway**.

### Build from Source

See [Build Instructions](#-build-instructions) below.

## 🔧 Build Instructions

### Option 1: Using Build Script (Easiest)

```bash
./build.sh
```

This script will automatically:
- Build the app in Release mode
- Create a DMG file in the `release/` folder
- Open the release folder when done

### Option 2: Using Xcode

#### Building for local use:

1. Open `MonkeyNote.xcodeproj` in Xcode
2. Select **Product > Scheme > Edit Scheme**
3. Set **Build Configuration** to **Release**
4. Press `⌘ + B` to build
5. Press `⌘ + Shift + K` then `⌘ + B` to clean and rebuild (if needed)
6. Select **Product > Show Build Folder in Finder**
7. Navigate to `Products/Release/` to find `MonkeyNote.app`
8. Optionally follow the [Create DMG](#-create-dmg-for-distribution) section below

#### Building for distribution (with Archive):

1. Open `MonkeyNote.xcodeproj` in Xcode
2. Select **Product > Archive** to create a release build
3. In the Organizer window, select the archive and click **Distribute App > Copy App**
4. Choose a destination folder to export the app
5. Optionally follow the [Create DMG](#-create-dmg-for-distribution) section below

### Option 3: Using Command Line

```bash
# Build the app
xcodebuild -project MonkeyNote.xcodeproj \
  -scheme MonkeyNote \
  -configuration Release \
  build

# The built app will be located at:
# ~/Library/Developer/Xcode/DerivedData/MonkeyNote-*/Build/Products/Release/MonkeyNote.app
```

## 📦 Create DMG for Distribution

After building, create a DMG file for easy distribution:

```bash
# Create a temporary folder
mkdir -p /tmp/MonkeyNote-dmg

# Copy the app
cp -R ~/Library/Developer/Xcode/DerivedData/MonkeyNote-*/Build/Products/Release/MonkeyNote.app \
  /tmp/MonkeyNote-dmg/

# Add Applications shortcut (optional, for drag-and-drop install)
ln -sf /Applications /tmp/MonkeyNote-dmg/Applications

# Create DMG
hdiutil create \
  -volname "MonkeyNote" \
  -srcfolder /tmp/MonkeyNote-dmg \
  -ov -format UDZO \
  MonkeyNote.dmg

# Cleanup
rm -rf /tmp/MonkeyNote-dmg
```

## ⚙️ Configuration

MonkeyNote stores all notes and settings in your local file system:

- **Notes location**: `~/Documents/MonkeyNote/`
- **Trash location**: `~/Documents/MonkeyNote/.trash/`
- **Settings**: Stored in UserDefaults

### Customizable Settings

Access settings via the gear icon in the sidebar:

- **Theme**: Light/Dark mode toggle
- **Font Family**: Monospaced, Rounded, or Serif
- **Font Size**: Adjustable text size
- **Cursor Settings**: Width, blinking, animation
- **Autocomplete**: Enable/disable, delay, opacity
- **Suggestion Mode**: Word or line completion
- **Markdown Rendering**: Toggle markdown preview
- **Vault Location**: Change notes storage location

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ + F` | Focus search field |
| `⏎` (in search) | Navigate to next match |
| `ESC` (in search) | Close search and return to editor |

## 🛠️ Development

### Architecture

MonkeyNote follows the MVVM (Model-View-ViewModel) architecture pattern:

- **Models**: `NoteModels.swift`, `VaultManager.swift` handle data structures and persistence
- **Views**: SwiftUI views for UI components
- **Components**: Reusable UI components and custom text editor

### Key Technologies

- **SwiftUI**: Modern declarative UI framework
- **AppKit**: Native macOS text system integration
- **FileManager**: File system operations
- **Combine**: Reactive programming for state management

### Building & Testing

```bash
# Build in debug mode
xcodebuild -project MonkeyNote.xcodeproj \
  -scheme MonkeyNote \
  -configuration Debug \
  build

# Run tests (if available)
xcodebuild test \
  -project MonkeyNote.xcodeproj \
  -scheme MonkeyNote
```

## 🐛 Troubleshooting

### Large Files Warning

MonkeyNote limits file size to 5,000 lines to maintain performance. Files exceeding this limit will show a warning icon and cannot be opened directly.

### Vault Location Issues

If notes don't appear, check:
1. Vault location in Settings
2. File permissions for the vault directory
3. Check trash folder for accidentally deleted notes

### Performance Issues

If the app feels sluggish:
1. Disable markdown rendering for large documents
2. Reduce autocomplete delay
3. Check for very large note files

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Built with SwiftUI and native macOS frameworks
- Inspired by minimalist note-taking applications
- Icon design by [Your Name]

## 📧 Contact

For bug reports and feature requests, please open an issue on GitHub.

---

<div align="center">
Made with ❤️ for macOS
</div>
