# SmartGradeScanner OMR upgrade notes

This package is a hardened revision of the supplied `scannerios-main` project. The goal is to make phone-camera OMR safer and more tolerant of ordinary paper capture problems while refusing ambiguous reads instead of silently assigning a wrong student or answer.

## Major changes

- Recalibrated the bundled physical answer-sheet geometry from the supplied reference image:
  - page ratio `591 / 518`
  - questions 1–17 in the left block
  - questions 18–20 in the upper middle block
  - 9-column × 10-row Student ID grid
  - Student ID prefix `320`
  - nine registration markers
- The scanner now reads only the question numbers that belong to the selected exam. A five-question exam therefore reads questions 1–5 only rather than treating later template rows as answers.
- The bundled form is explicitly limited to 20 questions because the physical reference sheet contains 20 answer rows.
- Added EXIF-orientation normalization before document geometry analysis.
- Added document candidate ranking by confidence, expected page ratio, area, and centering.
- Added guarded full-frame handling for pages that VisionKit has already cropped.
- Added Core Image perspective correction and canonical page sizing before OMR coordinates are applied.
- Replaced fixed global dark-pixel assumptions with local illumination-aware bubble measurements.
- Added per-sheet two-cluster calibration for blank/filled signals.
- Registration marks are searched locally as solid high-contrast dark squares.
- Added robust marker-based affine alignment with outlier rejection and reprojection error checks.
- Student ID and answer regions are validated separately; answer probes refuse overlap with the transformed ID region.
- Student ID requires exactly one clearly dominant marked digit in each column; unclear or multiply marked columns are rejected for manual review rather than guessed.
- Ambiguous/weak/multiple answer bubbles are surfaced as review states instead of being silently converted to a normal answer.
- Added image quality scoring, stronger camera focus/exposure/white-balance configuration, and quality-prioritized still capture.
- Updated review UI to show the aligned sheet, Student ID, paper confidence, warnings, and question-level status.
- Corrected `Info.plist` bundle metadata needed by IPA signing/install tools.
- Added a complete 1024×1024 AppIcon asset.
- GitHub Actions now captures compiler stderr and validates required built `Info.plist` fields before packaging the unsigned IPA.

## Reference-sheet validation performed during this revision

A pixel-level validation harness was run against the supplied reference sheet using the same ROI geometry and local-threshold formula implemented in the Swift reader.

- Original reference: 20/20 answer locations stable; Student ID `320234561204` recovered.
- Brighter synthetic exposure: 20/20 stable; ID unchanged.
- Darker synthetic exposure: 20/20 stable; ID unchanged.
- Mild Gaussian blur: 20/20 stable; ID unchanged.
- Uneven synthetic illumination gradient: 20/20 stable; ID unchanged.
- All nine registration markers scored strongly in the calibrated search windows.

These checks validate the supplied reference layout and algorithm logic; they are not a substitute for testing many real sheets from different phones, printers, pens, distances, shadows, folds, and handwriting styles.

## Engineering basis

The revision follows established document/OMR principles: document rectangle localization, perspective rectification, orientation normalization, local/adaptive illumination handling, registration-marker alignment, strict region-of-interest segmentation, and separate processing of ID and answer sections. Apple Vision/VisionKit/Core Image/AVFoundation documentation and modern OMR literature were used as the engineering basis.

## Verification in this environment

- All Swift source files pass `swiftc -parse` (62 Swift files).
- `Info.plist` parses successfully and contains required bundle/camera/photo keys.
- AppIcon catalog JSON parses successfully and points to a 1024×1024 RGB PNG.
- GitHub Actions YAML parses successfully as YAML.
- Full Xcode/iOS type-checking and device execution cannot be performed in this Linux container. Run the included GitHub Action or open the project in Xcode to perform the final Apple-platform build.

## v4 - portrait reference-sheet fallback
- Fixed the "alignment marks are insufficient/not distributed" failure on the supplied portrait 5-question reference image.
- Root cause: the original 20-question template expected a different page aspect ratio and a 9-marker layout, while the supplied portrait sheet has 6 large square registration markers.
- Added a separately calibrated 0.75 aspect-ratio portrait profile with six registration squares, exact 5-question bubble coordinates, and the 9-column Student ID grid.
- Scanner now retries this portrait profile only when the primary template cannot be aligned, preserving the existing 20-question/custom-template path.
- Alignment now respects each template's configured minimum marker count instead of hard-coding five markers for every six-marker layout.
