import Foundation
import CoreGraphics

struct StudentIDDetector: Sendable {
    func signalSamples(definition: StudentIDDefinition,
                       in image: CGImage,
                       transform: AlignmentTransform = .identity) -> [Double] {
        guard let gray = GrayImage(cgImage: image),
              !definition.columns.isEmpty,
              definition.digitRows.count == 10 else { return [] }
        return definition.columns.flatMap { column in
            definition.digitRows.compactMap { row in
                signal(column: column, row: row, gray: gray, transform: transform)?.signal
            }
        }
    }

    func detect(definition: StudentIDDefinition,
                in image: CGImage,
                profile: CalibrationProfile,
                transform: AlignmentTransform = .identity) -> (value: String?, confidence: Double, warning: String?) {
        guard let gray = GrayImage(cgImage: image),
              !definition.columns.isEmpty,
              definition.digitRows.count == 10 else {
            return (nil, 0, "Student ID grid is not configured.")
        }

        let transformedRegion = transform.apply(definition.region)
        guard !transformedRegion.isNull,
              transformedRegion.minX >= -0.03,
              transformedRegion.minY >= -0.03,
              transformedRegion.maxX <= 1.03,
              transformedRegion.maxY <= 1.03 else {
            return (nil, 0, "Student ID region is outside the detected sheet.")
        }

        var digits = ""
        var columnConfidences: [Double] = []
        columnConfidences.reserveCapacity(definition.columns.count)

        for column in definition.columns {
            let candidates = definition.digitRows.enumerated().compactMap { index, row -> (digit: Int, signal: Double, contrast: Double)? in
                guard let value = signal(column: column, row: row, gray: gray, transform: transform) else { return nil }
                return (index, value.signal, value.contrast)
            }.sorted { $0.signal > $1.signal }

            guard let best = candidates.first else {
                return (nil, 0, "Student ID could not be read.")
            }
            let second = candidates.dropFirst().first?.signal ?? 0
            let margin = best.signal - second
            let minimumMargin = max(0.09, profile.minimumSelectionMargin * 0.90)
            let minimumSignal = max(profile.decisionBoundary, profile.weakBoundary + 0.05)

            guard best.signal >= minimumSignal,
                  margin >= minimumMargin,
                  best.contrast >= max(0.05, profile.minimumLocalContrast) else {
                return (nil, max(0.20, min(0.55, margin + 0.25)), "Student ID is unclear. Retake the sheet or review the ID manually.")
            }

            if second >= profile.decisionBoundary {
                return (nil, 0.35, "More than one Student ID bubble appears filled in the same column.")
            }

            digits.append(String(best.digit))
            let signalStrength = max(0, (best.signal - profile.decisionBoundary) / max(1 - profile.decisionBoundary, 0.05))
            let digitConfidence = min(1, max(0.10, 0.42 + margin * 0.75 + signalStrength * 0.28 + best.contrast * 0.12))
            columnConfidences.append(digitConfidence)
        }

        let confidence = columnConfidences.reduce(0, +) / Double(max(columnConfidences.count, 1))
        let value = definition.prefix + digits
        guard value.allSatisfy(\.isNumber) else {
            return (nil, confidence * 0.5, "Student ID contains an invalid character.")
        }
        if confidence < 0.62 {
            return (value, confidence, "Student ID confidence is borderline; verify it before saving.")
        }
        return (value, confidence, nil)
    }

    private func signal(column: NormalizedRect,
                        row: NormalizedRect,
                        gray: GrayImage,
                        transform: AlignmentTransform) -> (signal: Double, contrast: Double)? {
        let cell = NormalizedRect(x: column.x,
                                  y: row.y,
                                  width: column.width,
                                  height: row.height)
        let transformed = transform.apply(cell)
        guard !transformed.isNull,
              transformed.midX >= 0, transformed.midX <= 1,
              transformed.midY >= 0, transformed.midY <= 1,
              transformed.width > 0.002, transformed.height > 0.002 else { return nil }

        let size = CGSize(width: gray.width, height: gray.height)
        let pixelRect = CGRect(x: transformed.minX * size.width,
                               y: transformed.minY * size.height,
                               width: transformed.width * size.width,
                               height: transformed.height * size.height)
        let stats = gray.statistics(in: pixelRect)
        let signal = min(1, max(0, stats.fillRatio * 0.72 + stats.darkness * 0.28))
        return (signal, stats.contrast)
    }
}
