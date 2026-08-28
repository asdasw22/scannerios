import Foundation

struct BubbleClassifier: Sendable {
    func classify(measurements: [BubbleMeasurement], profile: CalibrationProfile) -> (choices: [AnswerChoice], status: ResponseStatus, confidence: Double) {
        guard !measurements.isEmpty else { return ([], .invalidRegion, 0) }
        let ordered = measurements.sorted { $0.fillRatio > $1.fillRatio }
        let best = ordered[0]; let second = ordered.dropFirst().first?.fillRatio ?? 0
        let quality = max(0, min(1, best.confidence))
        let margin = best.fillRatio - second
        if best.fillRatio < profile.weakBoundary { return ([], .empty, max(0.45, quality)) }
        if best.fillRatio < profile.decisionBoundary { return ([best.choice], .weak, min(0.65, quality)) }
        if margin < profile.minimumSelectionMargin { return (ordered.filter { $0.fillRatio >= profile.weakBoundary }.map { $0.choice }, .multiple, min(0.72, quality)) }
        let confidence = min(0.99, max(0.05, 0.5 + margin * 0.9 + (best.fillRatio - profile.decisionBoundary) * 0.4) * quality)
        return ([best.choice], confidence < 0.65 ? .uncertain : .selected, confidence)
    }
}