import Foundation

struct ThresholdCalibrator: Sendable {
    func calibratedProfile(samples: [Double], base: CalibrationProfile = CalibrationProfile()) -> CalibrationProfile {
        let values = samples.filter { $0.isFinite }.map { min(1, max(0, $0)) }
        guard values.count >= 12 else { return base }

        let sorted = values.sorted()
        var lowCenter = percentile(sorted, 0.25)
        var highCenter = percentile(sorted, 0.90)
        guard highCenter - lowCenter >= 0.08 else { return base }

        var lowCluster: [Double] = []
        var highCluster: [Double] = []
        for _ in 0..<18 {
            lowCluster.removeAll(keepingCapacity: true)
            highCluster.removeAll(keepingCapacity: true)
            for value in values {
                if abs(value - lowCenter) <= abs(value - highCenter) {
                    lowCluster.append(value)
                } else {
                    highCluster.append(value)
                }
            }
            guard !lowCluster.isEmpty, !highCluster.isEmpty else { return base }
            let nextLow = lowCluster.reduce(0, +) / Double(lowCluster.count)
            let nextHigh = highCluster.reduce(0, +) / Double(highCluster.count)
            let orderedLow = min(nextLow, nextHigh)
            let orderedHigh = max(nextLow, nextHigh)
            if abs(orderedLow - lowCenter) + abs(orderedHigh - highCenter) < 0.0005 {
                lowCenter = orderedLow
                highCenter = orderedHigh
                break
            }
            lowCenter = orderedLow
            highCenter = orderedHigh
        }

        let separation = highCenter - lowCenter
        let filledFraction = Double(highCluster.count) / Double(values.count)
        guard separation >= 0.12,
              filledFraction >= 0.025,
              filledFraction <= 0.48 else { return base }

        var profile = base
        profile.blankCenter = lowCenter
        profile.filledCenter = highCenter
        profile.blankSpread = standardDeviation(lowCluster, mean: lowCenter)
        profile.filledSpread = standardDeviation(highCluster, mean: highCenter)
        profile.weakBoundary = min(0.92, lowCenter + separation * 0.24)
        profile.decisionBoundary = min(0.96, lowCenter + separation * 0.50)
        profile.minimumSelectionMargin = min(0.25, max(0.075, separation * 0.18))
        return profile
    }

    private func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let position = min(max(p, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        if lower == upper { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] * (1 - fraction) + sorted[upper] * fraction
    }

    private func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return sqrt(max(0, variance))
    }
}
