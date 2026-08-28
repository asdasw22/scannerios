import Foundation
import CoreGraphics

struct StudentIDDetector: Sendable {
    func detect(definition: StudentIDDefinition, in image: CGImage, profile: CalibrationProfile) -> (value: String?, confidence: Double, warning: String?) {
        guard let gray = GrayImage(cgImage: image), definition.columns.count > 0, definition.digitRows.count == 10 else { return (nil, 0, "Student ID grid is not configured.") }
        var digits = "", confidence = 1.0
        for column in definition.columns {
            let values = definition.digitRows.map { row -> Double in
                let rect = NormalizedRect(x: column.x, y: row.y, width: column.width, height: row.height).rect(in: CGSize(width: gray.width, height: gray.height))
                let stats = gray.statistics(in: rect)
                return min(1, max(0, stats.fillRatio * 0.75 + stats.darkness * 0.25))
            }
            let sorted = values.enumerated().sorted { $0.element > $1.element }
            guard let best = sorted.first else { return (nil, 0, "Student ID could not be read.") }
            let second = sorted.dropFirst().first?.element ?? 0
            guard best.element >= profile.weakBoundary, best.element - second >= profile.minimumSelectionMargin else { return (nil, 0.45, "Student ID is unclear and needs review.") }
            digits.append(String(best.offset)); confidence *= min(1, max(0.1, best.element - second + 0.5))
        }
        return (definition.prefix + digits, confidence, nil)
    }
}