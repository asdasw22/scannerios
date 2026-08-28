import SwiftUI
import UIKit

struct CorrectedSheetOverlay: View {
    let image: UIImage
    let result: ExamResult
    let template: TemplateDefinition?
    @State private var selectedQuestion: Int?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().scaledToFit()
                if let template {
                    ForEach(result.responses) { response in
                        if let question = template.questions.first(where: { $0.number == response.questionNumber }) {
                            let rect = normalizedBounds(for: question, in: proxy.size)
                            RoundedRectangle(cornerRadius: 5).stroke(color(for: response.status), lineWidth: selectedQuestion == response.questionNumber ? 4 : 2).frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY).contentShape(Rectangle()).onTapGesture { selectedQuestion = response.questionNumber }
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.aspectRatio(0.707, contentMode: .fit).sheet(item: Binding(get: { selectedQuestion.map { QuestionSelection(number: $0) } }, set: { selectedQuestion = $0?.number })) { selection in
            if let response = result.responses.first(where: { $0.questionNumber == selection.number }) { VStack(spacing: 12) { Text("Question \(selection.number)").font(.title2.bold()); Text("Student: \(response.selectedChoices.map { $0.rawValue }.joined(separator: " + ").ifEmpty("Empty"))"); Text("Correct: \(response.correctChoice?.rawValue ?? "—")").foregroundStyle(.secondary); Text("Confidence: \(response.confidence * 100, specifier: "%.0f")%").foregroundStyle(.secondary); Spacer() }.padding().presentationDetents([.medium]) }
        }
    }

    private func normalizedBounds(for question: TemplateQuestionDefinition, in size: CGSize) -> CGRect { guard let first = question.bubbles.first, let last = question.bubbles.last else { return .zero }; let minX = min(first.rect.x, last.rect.x), maxX = max(first.rect.x + first.rect.width, last.rect.x + last.rect.width); return CGRect(x: minX * size.width, y: first.rect.y * size.height, width: (maxX - minX) * size.width, height: first.rect.height * size.height) }
    private func color(for status: ResponseStatus) -> Color { switch status { case .selected: return .green; case .empty: return .gray; case .multiple: return .red; default: return .orange } }
}

private struct QuestionSelection: Identifiable { let number: Int; var id: Int { number } }
private extension String { func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self } }