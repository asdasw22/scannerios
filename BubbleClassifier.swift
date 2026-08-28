import Foundation

struct BubbleClassifier: Sendable {
  func classify(
    measurements: [BubbleMeasurement],
    profile: CalibrationProfile
  ) -> (choices: [AnswerChoice], status: ResponseStatus, confidence: Double) {
    guard measurements.count >= 2 else { return ([], .invalidRegion, 0) }
    let ordered = measurements.sorted { $0.fillRatio > $1.fillRatio }
    guard let best = ordered.first else { return ([], .invalidRegion, 0) }
    let second = ordered.dropFirst().first
    let secondSignal = second?.fillRatio ?? 0
    let margin = best.fillRatio - secondSignal
    let localQuality = min(1, max(0, best.confidence))

    guard localQuality >= 0.18 else {
      return ([best.choice], .invalidRegion, min(0.25, localQuality))
    }

    let separation = max(profile.filledCenter - profile.blankCenter, 0.10)
    let normalizedStrength = min(1, max(0, (best.fillRatio - profile.blankCenter) / separation))

    if best.fillRatio < profile.weakBoundary {
      let blankGap = max(0, profile.weakBoundary - best.fillRatio)
      let confidence = min(0.99, max(0.55, 0.67 + blankGap * 0.85)) * max(0.62, localQuality)
      return ([], .empty, confidence)
    }

    if best.fillRatio < profile.decisionBoundary {
      let confidence = min(
        0.64, max(0.28, localQuality * 0.52 + normalizedStrength * 0.28 + margin * 0.30))
      return ([best.choice], .weak, confidence)
    }

    let confidentlyMarked = ordered.filter {
      $0.fillRatio >= profile.decisionBoundary && $0.confidence >= 0.18
    }
    if confidentlyMarked.count >= 2 {
      let selected = confidentlyMarked.map(\.choice)
      let confidence = min(0.78, max(0.36, localQuality * 0.50 + (1 - min(margin, 1)) * 0.20))
      return (selected, .multiple, confidence)
    }

    if margin < profile.minimumSelectionMargin {
      let nearby = ordered.filter {
        $0.fillRatio >= profile.weakBoundary
          && best.fillRatio - $0.fillRatio < profile.minimumSelectionMargin
      }
      if nearby.count >= 2 {
        return (nearby.map(\.choice), .multiple, min(0.70, max(0.34, localQuality * 0.56)))
      }
      return (
        [best.choice], .uncertain,
        min(0.66, max(0.32, localQuality * 0.58 + normalizedStrength * 0.10))
      )
    }

    let boundaryDistance = max(0, best.fillRatio - profile.decisionBoundary)
    let confidence = min(
      0.997,
      max(
        0.05,
        0.44
          + margin * 0.78
          + boundaryDistance * 0.44
          + normalizedStrength * 0.16
          + localQuality * 0.12))
    return ([best.choice], confidence < 0.70 ? .uncertain : .selected, confidence)
  }
}
