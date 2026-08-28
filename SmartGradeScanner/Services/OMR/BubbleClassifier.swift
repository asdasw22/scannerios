import Foundation

struct BubbleClassifier: Sendable {
    func classify(measurements: [BubbleMeasurement],
                  profile: CalibrationProfile) -> (choices: [AnswerChoice], status: ResponseStatus, confidence: Double) {
        guard !measurements.isEmpty else { return ([], .invalidRegion, 0) }
        let ordered = measurements.sorted { $0.fillRatio > $1.fillRatio }
        guard let best = ordered.first else { return ([], .invalidRegion, 0) }
        let second = ordered.dropFirst().first
        let secondSignal = second?.fillRatio ?? 0
        let margin = best.fillRatio - secondSignal
        let localQuality = min(1, max(0, best.confidence))

        if localQuality < 0.16 {
            return ([best.choice], .invalidRegion, min(0.25, localQuality))
        }

        if best.fillRatio < profile.weakBoundary {
            let blankDistance = max(0, profile.weakBoundary - best.fillRatio)
            let confidence = min(0.98, max(0.55, 0.62 + blankDistance * 0.9)) * max(0.55, localQuality)
            return ([], .empty, confidence)
        }

        if best.fillRatio < profile.decisionBoundary {
            let weakConfidence = min(0.62, max(0.30, localQuality * 0.58 + margin * 0.35))
            return ([best.choice], .weak, weakConfidence)
        }

        let definitelyMarked = ordered.filter {
            $0.fillRatio >= profile.decisionBoundary && $0.confidence >= 0.16
        }
        if definitelyMarked.count >= 2 {
            let selected = definitelyMarked.map(\.choice)
            let confidence = min(0.74, max(0.35, localQuality * 0.55 + (1 - margin) * 0.18))
            return (selected, .multiple, confidence)
        }

        if margin < profile.minimumSelectionMargin {
            let nearby = ordered.filter {
                $0.fillRatio >= profile.weakBoundary && best.fillRatio - $0.fillRatio < profile.minimumSelectionMargin
            }
            if nearby.count >= 2 {
                return (nearby.map(\.choice), .multiple, min(0.70, max(0.35, localQuality * 0.60)))
            }
            return ([best.choice], .uncertain, min(0.62, max(0.32, localQuality * 0.62)))
        }

        let boundaryDistance = max(0, best.fillRatio - profile.decisionBoundary)
        let confidence = min(0.995,
                             max(0.05,
                                 0.48
                                 + margin * 0.72
                                 + boundaryDistance * 0.42
                                 + localQuality * 0.18))
        return ([best.choice], confidence < 0.67 ? .uncertain : .selected, confidence)
    }
}
