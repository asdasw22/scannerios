import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct ScannerView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var viewModel: ScannerViewModel
    @State private var selectedPhoto: PhotosPickerItem?

    init(exam: Exam? = nil) {
        _viewModel = StateObject(wrappedValue: ScannerViewModel(exam: exam))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: viewModel.camera.session).ignoresSafeArea()
            VStack {
                HStack {
                    Label(viewModel.exam?.name ?? "Quick Scan", systemImage: "doc.text")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding()
                Spacer()
                scanGuide
                controls
            }
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.startCamera() }
        .onDisappear { viewModel.stopCamera() }
        .onReceive(viewModel.camera.$lastImageData.compactMap { $0 }) { imageData in
            viewModel.process(imageData: imageData)
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    viewModel.process(imageData: data)
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingDocumentScanner) {
            DocumentScannerView(onImageData: {
                viewModel.process(imageData: $0)
                viewModel.isShowingDocumentScanner = false
            }, onCancel: {
                viewModel.isShowingDocumentScanner = false
            })
        }
        .sheet(isPresented: Binding(get: {
            viewModel.result != nil && !viewModel.isProcessing
        }, set: {
            if !$0 { viewModel.result = nil }
        })) {
            if let result = viewModel.result {
                ScanReviewView(result: result, exam: viewModel.exam, context: context)
            }
        }
        .alert(item: $viewModel.error) { error in
            Alert(title: Text("Scan failed"),
                  message: Text(error.localizedDescription),
                  dismissButton: .default(Text("OK")))
        }
    }

    private var scanGuide: some View {
        RoundedRectangle(cornerRadius: 22)
            .stroke(viewModel.isProcessing ? .orange : (viewModel.camera.liveDetector.isReady ? .green : .white),
                    style: StrokeStyle(lineWidth: 3, dash: [10]))
            .frame(maxWidth: 460)
            .aspectRatio(CGFloat(viewModel.templateAspectRatio), contentMode: .fit)
            .padding(24)
            .overlay(alignment: .bottom) {
                Text(viewModel.isProcessing
                     ? viewModel.stage.rawValue
                     : (viewModel.camera.liveDetector.isReady
                        ? "Ready · hold steady"
                        : "Fit the entire sheet and black markers inside the frame"))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.68), in: Capsule())
                    .padding(.bottom, 36)
            }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button { viewModel.isShowingDocumentScanner = true } label: {
                Label("Document", systemImage: "doc.viewfinder")
            }
            .buttonStyle(.borderedProminent)

            Button { viewModel.capture() } label: {
                Image(systemName: "circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
                    .overlay { Circle().stroke(.black.opacity(0.3), lineWidth: 2) }
            }
            .disabled(viewModel.isProcessing)

            Spacer().frame(width: 90)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
    }
}

private struct ScanReviewView: View {
    let result: OMRProcessingResult
    let exam: Exam?
    let context: ModelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let data = result.alignedImageData, let image = UIImage(data: data) {
                    Section("Aligned sheet") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Section {
                    LabeledContent("Student", value: result.studentID ?? "Needs review")
                    LabeledContent("Detected answers", value: "\(result.questions.count) / \(exam?.questions.count ?? result.questions.count)")
                    LabeledContent("Paper confidence", value: result.paperConfidence.formatted(.percent.precision(.fractionLength(0))))
                    if result.needsReview {
                        Label("Some fields need manual review", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                if !result.warnings.isEmpty {
                    Section("Checks") {
                        ForEach(result.warnings, id: \.self) { warning in
                            Label(warning, systemImage: "info.circle")
                                .font(.footnote)
                        }
                    }
                }

                Section("Questions") {
                    ForEach(result.questions) { item in
                        HStack {
                            Text("Q\(item.questionNumber)").frame(width: 42, alignment: .leading)
                            Text(item.selectedChoices.map { $0.rawValue }.joined(separator: " + ").ifEmpty("Empty"))
                            Spacer()
                            StatusBadge(status: item.status)
                            Text("\(item.confidence * 100, specifier: "%.0f")%")
                                .font(.caption.monospacedDigit())
                        }
                    }
                }

                Section {
                    Button("Save Result") {
                        let student = result.studentID.flatMap { id in
                            (try? context.fetch(FetchDescriptor<Student>()))?.first { $0.studentID == id }
                        }
                        let model = ExamResult(omrResult: result,
                                               exam: exam,
                                               student: student,
                                               maximumScore: exam?.maximumScore)
                        if let exam { exam.results.append(model) }
                        context.insert(model)
                        try? context.save()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("Review Scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { dismiss() }
                }
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
