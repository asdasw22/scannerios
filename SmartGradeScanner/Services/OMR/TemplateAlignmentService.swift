import Foundation

struct TemplateAlignmentReport: Sendable {
    let matchedMarkers: Int
    let confidence: Double
    let isCompatible: Bool
}

struct TemplateAlignmentService: Sendable {
    func validate(markers: [DetectedMarker], template: TemplateDefinition) -> TemplateAlignmentReport {
        let required = max(template.calibration.minimumMarkerCount, template.markers.isEmpty ? 0 : 1)
        let confidence = markers.isEmpty && required > 0 ? 0 : markers.map { $0.confidence }.reduce(0, +) / Double(max(markers.count, 1))
        return TemplateAlignmentReport(matchedMarkers: markers.count, confidence: confidence, isCompatible: markers.count >= required && confidence >= 0.55)
    }
}