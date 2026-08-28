# SmartGrade Scanner

SmartGrade Scanner is a local-first iOS/iPadOS answer-sheet scanner built with SwiftUI, SwiftData, Vision, VisionKit, Core Image, AVFoundation, PhotosUI, and PDFKit.

## Open and build

1. Copy `C:\Users\user\Desktop\scanner` to a Mac.
2. Open `SmartGradeScanner.xcodeproj` in Xcode 16 or newer.
3. Select the `SmartGradeScanner` scheme and choose an iPhone or iPad simulator for UI work.
4. For camera testing, choose a physical iPhone/iPad, select a valid Apple Developer Team, and use a unique bundle identifier in Signing & Capabilities.
5. Run `Product > Build` or `Product > Test`.
6. For distribution, select a real device, configure signing, then use `Product > Archive`.

The current development environment is Windows, so Xcode, the iOS SDK, Simulator, unit tests, and Archive cannot be executed here. The project file, source membership, resources, shared scheme, and test target are included for Xcode on macOS.

## OMR workflow

- `OMRProcessor` is UI-independent and processes paper detection, perspective correction, grayscale normalization, registration validation, ROI sampling, calibration, confidence, Student ID, and grading.
- Bubble decisions use local background-normalized darkness, dark-pixel ratio, contrast, best-vs-second-best margin, and a per-template `CalibrationProfile`.
- Weak, uncertain, empty, and multiple marks are represented explicitly. Low-confidence results require review instead of being silently guessed.
- Template coordinates are normalized to `0...1`, so different camera resolutions do not change the template geometry.
- Answer-sheet images are processed and persisted locally by default.

## Reference sheet profile

The included sample profile reflects the supplied sheet layout: 20 questions, five choices (`A...E`), a nine-column by ten-row Student ID grid, optional `320` prefix, and registration-marker definitions. The Template Editor is the authoritative way to calibrate exact positions from a clean answer-key sheet; the supplied screenshot is not stored in the app.

## Included tests

The `SmartGradeScannerTests` target covers selected, empty, weak, multiple, and low-confidence marks, adaptive calibration, weighted grading, normalized coordinates, perspective error measurement, and Student ID definition shape.