import Foundation

struct ThresholdCalibrator: Sendable {
    func calibratedProfile(samples: [Double], base: CalibrationProfile = CalibrationProfile()) -> CalibrationProfile {
        guard samples.count >= 4 else { return base }
        let sorted = samples.sorted(); let midpoint = sorted[sorted.count / 2]
        let lower = sorted.filter { $0 <= midpoint }; let upper = sorted.filter { $0 > midpoint }
        guard let low = lower.last, let high = upper.first, high - low >= 0.06 else { return base }
        var profile = base
        profile.blankCenter = lower.reduce(0, +) / Double(lower.count)
        profile.filledCenter = upper.reduce(0, +) / Double(upper.count)
        profile.decisionBoundary = (profile.blankCenter + profile.filledCenter) / 2
        profile.weakBoundary = profile.blankCenter + (profile.decisionBoundary - profile.blankCenter) * 0.55
        profile.minimumSelectionMargin = max(0.04, (high - low) * 0.3)
        return profile
    }
}