# Downloads Feature Testing Guide

## Overview
The merge panel now supports saving videos to the Downloads folder on macOS, Windows, and Android platforms.

## Features Added

### 1. Video Thumbnail Display
- Automatically displays video thumbnail when final video is ready
- Clickable thumbnail with play button overlay opens video preview
- Uses `video_thumbnail` package for thumbnail generation

### 2. Downloads Button
- New green "Downloads-қа" button next to "Photos-қа" button
- Available on: macOS, Windows, and Android
- Copies final video to Downloads folder
- Shows success notification with "Ашу" (Open) button

### 3. Platform-Specific Behavior

#### macOS
- Copies video to `~/Downloads` folder
- Uses `getDownloadsDirectory()` with fallback to manual path
- "Ашу" button opens Finder and selects the file (`open -R`)
- **Requires**: App rebuild to apply entitlements

#### Windows
- Copies video to `%USERPROFILE%\Downloads` folder
- Uses `getDownloadsDirectory()` with fallback to manual path
- "Ашу" button opens Explorer and selects the file (`explorer.exe /select,`)

#### Android
- Saves video using `image_gallery_saver` package
- Automatically saves to Downloads/Movies folder based on Android version
- No "Ашу" button on Android (not needed - file appears in Files app)

## Testing Instructions

### macOS Testing
```bash
# 1. Clean and rebuild to apply entitlements
flutter clean
flutter build macos

# 2. Run the app
flutter run -d macos

# 3. Test steps:
# - Complete video processing
# - Verify thumbnail appears
# - Click "Downloads-қа" button
# - Check ~/Downloads folder for the video
# - Click "Ашу" to verify Finder opens with file selected
```

### Windows Testing
```bash
# 1. Run the app (requires Windows machine)
flutter run -d windows

# 2. Test steps:
# - Complete video processing
# - Verify thumbnail appears
# - Click "Downloads-қа" button
# - Check %USERPROFILE%\Downloads folder for the video
# - Click "Ашу" to verify Explorer opens with file selected
```

### Android Testing
```bash
# 1. Connect Android device or start emulator
flutter devices

# 2. Run the app
flutter run -d <device-id>

# 3. Test steps:
# - Complete video processing
# - Verify thumbnail appears
# - Click "Downloads-қа" button
# - Open Files app and check Downloads folder
# - Note: "Ашу" button not shown on Android
```

## Expected File Naming
Videos are saved with timestamp-based names:
```
translated_video_<milliseconds_since_epoch>.mp4
```

Example: `translated_video_1765348331850.mp4`

## Permissions

### macOS Entitlements (Already Added)
- `com.apple.security.files.downloads.read-write` - Allows Downloads folder access

### Android Permissions
- Uses `image_gallery_saver` which handles permissions automatically
- App will request storage permissions if needed

### Windows Permissions
- No special permissions needed - standard file system access

## Troubleshooting

### macOS: "Operation not permitted" Error
**Solution**: Rebuild the app to apply entitlements
```bash
flutter clean
flutter build macos
flutter run -d macos
```

### Windows: Cannot find Downloads folder
**Solution**: Code automatically falls back to Documents folder if Downloads not found

### Android: Save failed
**Solution**: Grant storage permissions when prompted

## Files Modified
1. `lib/widgets/merge_panel.dart` - Main functionality
2. `macos/Runner/DebugProfile.entitlements` - macOS debug permissions
3. `macos/Runner/Release.entitlements` - macOS release permissions

## Code Analysis
All changes pass Flutter static analysis:
```bash
flutter analyze lib/widgets/merge_panel.dart
# Result: No issues found!
```
