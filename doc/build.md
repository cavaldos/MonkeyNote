# Building MonkeyNote from Source

## Option 1: Using Build Script (Easiest)

```bash
./build.sh
```

This script will automatically:
- Build the app in Release mode
- Create a DMG file in the `release/` folder
- Open the release folder when done

## Option 2: Using Xcode

### Building for local use:

1. Open `MonkeyNote.xcodeproj` in Xcode
2. Select **Product > Scheme > Edit Scheme**
3. Set **Build Configuration** to **Release**
4. Press `⌘ + B` to build
5. Press `⌘ + Shift + K` then `⌘ + B` to clean and rebuild (if needed)
6. Select **Product > Show Build Folder in Finder**
7. Navigate to `Products/Release/` to find `MonkeyNote.app`

### Building for distribution (with Archive):

1. Open `MonkeyNote.xcodeproj` in Xcode
2. Select **Product > Archive** to create a release build
3. In the Organizer window, select the archive and click **Distribute App > Copy App**
4. Choose a destination folder to export the app
