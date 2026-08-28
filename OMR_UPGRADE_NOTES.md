# SmartGradeScanner OMR v5

This revision hardens the scanner for the supplied 591 x 520 landscape answer sheet.

## Core fixes

- Removed automatic fallback to a different page template after marker/alignment failure.
- Question rows and Student ID grid now use separate parsers, separate calibration populations, and non-overlapping protected zones.
- A-D exams physically ignore the E bubble column instead of detecting it and filtering later.
- Registration alignment now rejects large scale, rotation, shear, translation/drift, or poor marker coverage.
- Document detection rejects small inner rectangles such as the Student ID table as page candidates.
- Bubble analysis uses an inner elliptical mask to reduce influence from printed circle borders.
- Student ID requires exactly one confident digit per column and never guesses on ambiguous columns.
- Scan review includes confidence, correct answer, per-bubble signal values, and optional OMR debug overlays.
- Template Editor previews answer, ID, and registration zones and can reapply the exact calibrated reference profile.

## Reference profile

- Profile: `ReferenceSheet-591x520`
- Revision: 5
- Questions: up to 20
- Choices: A-D or A-E
- Student ID: 9 columns x 10 digits with `320` prefix
- Registration anchors: 9

The scanner deliberately fails closed when the sheet geometry does not match the configured profile. This is safer than returning a plausible but incorrect grade.
