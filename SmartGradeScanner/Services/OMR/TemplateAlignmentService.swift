import Foundation
import CoreGraphics

struct AlignmentTransform: Sendable, Equatable {
    var a: Double
    var b: Double
    var c: Double
    var d: Double
    var e: Double
    var f: Double

    static let identity = AlignmentTransform(a: 1, b: 0, c: 0, d: 0, e: 1, f: 0)

    func apply(_ point: CGPoint) -> CGPoint {
        let x = Double(point.x)
        let y = Double(point.y)
        return CGPoint(x: a * x + b * y + c,
                       y: d * x + e * y + f)
    }

    func apply(_ rect: NormalizedRect) -> CGRect {
        let points = [
            CGPoint(x: rect.x, y: rect.y),
            CGPoint(x: rect.x + rect.width, y: rect.y),
            CGPoint(x: rect.x + rect.width, y: rect.y + rect.height),
            CGPoint(x: rect.x, y: rect.y + rect.height)
        ].map(apply)
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct TemplateAlignmentReport: Sendable {
    let matchedMarkers: Int
    let confidence: Double
    let isCompatible: Bool
    let transform: AlignmentTransform
    let reprojectionError: Double
    let coverage: Double
}

struct TemplateAlignmentService: Sendable {
    func validate(markers: [DetectedMarker], template: TemplateDefinition) -> TemplateAlignmentReport {
        guard !template.markers.isEmpty else {
            return TemplateAlignmentReport(matchedMarkers: 0,
                                           confidence: 1,
                                           isCompatible: true,
                                           transform: .identity,
                                           reprojectionError: 0,
                                           coverage: 1)
        }

        let required = template.markers.count >= 6
            ? max(template.calibration.minimumMarkerCount, 5)
            : min(template.markers.count, max(template.calibration.minimumMarkerCount, 3))

        guard markers.count >= 3, let initial = fitAffine(markers) else {
            return TemplateAlignmentReport(matchedMarkers: markers.count,
                                           confidence: 0,
                                           isCompatible: false,
                                           transform: .identity,
                                           reprojectionError: .greatestFiniteMagnitude,
                                           coverage: markerCoverage(markers))
        }

        let initialResiduals = markers.map { residual(marker: $0, transform: initial) }
        let medianResidual = median(initialResiduals)
        let rejectionLimit = max(template.calibration.markerReprojectionTolerance * 1.8,
                                 max(0.012, medianResidual * 2.6))
        let inliers = zip(markers, initialResiduals).compactMap { marker, error in
            error <= rejectionLimit ? marker : nil
        }
        let transform = (inliers.count >= 3 ? fitAffine(inliers) : nil) ?? initial
        let usedMarkers = inliers.count >= 3 ? inliers : markers
        let errors = usedMarkers.map { residual(marker: $0, transform: transform) }
        let reprojectionError = errors.reduce(0, +) / Double(max(errors.count, 1))
        let coverage = markerCoverage(usedMarkers)
        let markerConfidence = usedMarkers.map(\.confidence).reduce(0, +) / Double(max(usedMarkers.count, 1))
        let errorScore = max(0, 1 - reprojectionError / max(template.calibration.markerReprojectionTolerance * 2.0, 0.02))
        let coverageScore = min(1, coverage / 0.28)
        let confidence = min(1, max(0, markerConfidence * 0.58 + errorScore * 0.27 + coverageScore * 0.15))

        let xs = usedMarkers.map { $0.expectedCenter.x }
        let ys = usedMarkers.map { $0.expectedCenter.y }
        let widthSpan = Double((xs.max() ?? 0) - (xs.min() ?? 0))
        let heightSpan = Double((ys.max() ?? 0) - (ys.min() ?? 0))
        let distributed = widthSpan >= 0.30 && heightSpan >= 0.28
        let isCompatible = usedMarkers.count >= required
            && distributed
            && markerConfidence >= 0.56
            && reprojectionError <= max(template.calibration.markerReprojectionTolerance * 1.45, 0.032)
            && confidence >= 0.58

        return TemplateAlignmentReport(matchedMarkers: usedMarkers.count,
                                       confidence: confidence,
                                       isCompatible: isCompatible,
                                       transform: transform,
                                       reprojectionError: reprojectionError,
                                       coverage: coverage)
    }

    private func fitAffine(_ markers: [DetectedMarker]) -> AlignmentTransform? {
        guard markers.count >= 3 else { return nil }
        var xx = 0.0, xy = 0.0, yy = 0.0, xSum = 0.0, ySum = 0.0
        var xu = 0.0, yu = 0.0, uSum = 0.0
        var xv = 0.0, yv = 0.0, vSum = 0.0

        for marker in markers {
            let x = Double(marker.expectedCenter.x)
            let y = Double(marker.expectedCenter.y)
            let u = Double(marker.center.x)
            let v = Double(marker.center.y)
            xx += x * x
            xy += x * y
            yy += y * y
            xSum += x
            ySum += y
            xu += x * u
            yu += y * u
            uSum += u
            xv += x * v
            yv += y * v
            vSum += v
        }

        let n = Double(markers.count)
        let matrix = [
            [xx, xy, xSum],
            [xy, yy, ySum],
            [xSum, ySum, n]
        ]
        guard let xCoefficients = solve3x3(matrix, [xu, yu, uSum]),
              let yCoefficients = solve3x3(matrix, [xv, yv, vSum]) else { return nil }

        return AlignmentTransform(a: xCoefficients[0],
                                  b: xCoefficients[1],
                                  c: xCoefficients[2],
                                  d: yCoefficients[0],
                                  e: yCoefficients[1],
                                  f: yCoefficients[2])
    }

    private func solve3x3(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        guard matrix.count == 3, matrix.allSatisfy({ $0.count == 3 }), vector.count == 3 else { return nil }
        var augmented = (0..<3).map { matrix[$0] + [vector[$0]] }

        for pivot in 0..<3 {
            var bestRow = pivot
            for row in pivot..<3 where abs(augmented[row][pivot]) > abs(augmented[bestRow][pivot]) {
                bestRow = row
            }
            guard abs(augmented[bestRow][pivot]) > 1e-10 else { return nil }
            if bestRow != pivot { augmented.swapAt(bestRow, pivot) }

            let divisor = augmented[pivot][pivot]
            for column in pivot..<4 { augmented[pivot][column] /= divisor }

            for row in 0..<3 where row != pivot {
                let factor = augmented[row][pivot]
                for column in pivot..<4 {
                    augmented[row][column] -= factor * augmented[pivot][column]
                }
            }
        }
        return [augmented[0][3], augmented[1][3], augmented[2][3]]
    }

    private func residual(marker: DetectedMarker, transform: AlignmentTransform) -> Double {
        let projected = transform.apply(marker.expectedCenter)
        return hypot(Double(projected.x - marker.center.x), Double(projected.y - marker.center.y))
    }

    private func markerCoverage(_ markers: [DetectedMarker]) -> Double {
        guard markers.count >= 2 else { return 0 }
        let xs = markers.map { Double($0.expectedCenter.x) }
        let ys = markers.map { Double($0.expectedCenter.y) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return max(0, maxX - minX) * max(0, maxY - minY)
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
