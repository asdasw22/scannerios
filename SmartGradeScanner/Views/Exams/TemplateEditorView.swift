import SwiftUI
import SwiftData
import UIKit

struct TemplateEditorView: View {
    @Bindable var exam: Exam
    @State private var selectedQuestion: Int?
    @State private var showingAdd = false
    var body: some View {
        Group {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationSplitView { questionList } detail: { editorCanvas }
            } else { VStack(spacing: 0) { editorCanvas; Divider(); questionList.frame(maxHeight: 220) } }
            #else
            editorCanvas
            #endif
        }
        .navigationTitle("Template Editor")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showingAdd) { AddQuestionSheet(exam: exam) }
    }
    private var questionList: some View {
        List(exam.questions.sorted { $0.number < $1.number }, selection: $selectedQuestion) { question in
            HStack { Text("Q\(question.number)"); Spacer(); Text(question.correctAnswerRaw ?? "—").foregroundStyle(.secondary) }.tag(question.number)
        }.navigationTitle("Questions")
    }
    private var editorCanvas: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color(uiColor: .secondarySystemBackground)).aspectRatio(CGFloat(exam.template?.definition.pageAspectRatio ?? SampleDataSeeder.template().pageAspectRatio), contentMode: .fit).frame(minWidth: 360)
                VStack(alignment: .leading, spacing: 8) {
                    Text(exam.name).font(.title3.bold()).padding(.bottom, 6)
                    Text("Template coordinate space").font(.caption).foregroundStyle(.secondary)
                    ForEach(exam.questions.sorted { $0.number < $1.number }) { question in
                        HStack(spacing: 5) {
                            Text("\(question.number)").font(.caption2).frame(width: 22, alignment: .trailing)
                            ForEach(question.choices) { choice in Circle().strokeBorder(selectedQuestion == question.number ? Color.accentColor : .secondary, lineWidth: 1.5).frame(width: 18, height: 18).overlay(Text(choice.rawValue).font(.system(size: 7))) }
                        }.contentShape(Rectangle()).onTapGesture { selectedQuestion = question.number }
                    }
                    Spacer(minLength: 10)
                    Text("Student ID grid · 9 columns × 10 rows").font(.caption).foregroundStyle(.secondary)
                }.padding(32)
            }.frame(width: 420).aspectRatio(CGFloat(exam.template?.definition.pageAspectRatio ?? SampleDataSeeder.template().pageAspectRatio), contentMode: .fit)
        }.background(.background)
    }
}

private struct AddQuestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var exam: Exam
    @State private var choices = 5
    var body: some View {
        NavigationStack { Form { Stepper("Choices: \(choices)", value: $choices, in: 2...5); Button("Add Question") { let next = (exam.questions.map { $0.number }.max() ?? 0) + 1; exam.questions.append(Question(number: next, choices: Array(AnswerChoice.allCases.prefix(choices)))); dismiss() } }.navigationTitle("Add Question").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }
    }
}