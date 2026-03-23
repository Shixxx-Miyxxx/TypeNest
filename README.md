# TypeNest

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)](https://www.swift.org/)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

TypeNest is a native macOS app for sorting files by extension with a preview-first workflow.
You select a folder, review exactly what will happen, then run the operation as Move or Copy.

## Download

[![Download TypeNest for macOS](https://img.shields.io/badge/Download-TypeNest%20for%20macOS-1f883d?style=for-the-badge&logo=apple)](https://github.com/Shixxx-Miyxxx/TypeNest/raw/main/dist/TypeNest-macOS-Release-clean.app.zip)

- Direct package: `TypeNest-macOS-Release-clean.app.zip`
- If macOS warns about an unidentified developer, right-click `TypeNest.app` and choose **Open** once.
- Future tagged releases: [GitHub Releases](https://github.com/Shixxx-Miyxxx/TypeNest/releases)

## Why TypeNest

- Native SwiftUI macOS application (no Electron dependency).
- Preview plan before applying any file operation.
- Move and copy execution modes.
- Collision handling: Skip, Rename, or Overwrite.
- Recursive scan support.
- `RAW + JPEG` preset for camera workflows (`jpg/jpeg` merge supported).
- `Custom Extensions` preset for your own extension list.

## How To Use

1. Open TypeNest and click **Choose Folder…**.
2. Select a preset and execution settings.
3. Click **Preview Plan** and inspect the table results.
4. Use filters/search if needed to verify planned operations.
5. Click **Run** to apply changes.
6. Check the summary cards for executed/skipped/errors.

## Requirements

- macOS 14.0 or later
- Apple Silicon or Intel Mac

## Build From Source

```bash
open TypeNest.xcodeproj
```

or from terminal:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project TypeNest.xcodeproj \
  -scheme TypeNest \
  -configuration Release \
  -sdk macosx \
  -derivedDataPath .build/DerivedData \
  build CODE_SIGNING_ALLOWED=NO
```

The built app is generated at:

```text
.build/DerivedData/Build/Products/Release/TypeNest.app
```

## Run Tests

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Project Structure

- `TypeNestApp/`: SwiftUI app target and screens.
- `Sources/TypeNestCore/`: planner, executor, presets, and models.
- `Tests/TypeNestCoreTests/`: core behavior tests.
- `dist/`: prebuilt downloadable app package.

## License

This project is released under the MIT License. See [LICENSE](./LICENSE).
