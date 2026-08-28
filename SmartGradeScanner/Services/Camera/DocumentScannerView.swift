import SwiftUI
import VisionKit
import UIKit

struct DocumentScannerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController { let controller = VNDocumentCameraViewController(); controller.delegate = context.coordinator; return controller }
    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.onCancel() }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) { if scan.pageCount > 0 { parent.onImage(scan.imageOfPage(at: 0)) } }
    }
}