import Foundation
import SwiftData

enum SampleDataSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<Classroom>()
        guard (try? context.fetchCount(descriptor)) == 0 else { return }
        let classroom = Classroom(name: "Grade 8A", grade: "Grade 8", section: "A")
        context.insert(classroom)
        [
            Student(studentID: "320234561204", name: "Ahmad Ali", grade: "Grade 8", section: "A", classroom: classroom),
            Student(studentID: "320234561205", name: "Omar Khaled", grade: "Grade 8", section: "A", classroom: classroom),
            Student(studentID: "320234561206", name: "Sara Hassan", grade: "Grade 8", section: "A", classroom: classroom),
            Student(studentID: "320234561207", name: "Lina Samir", grade: "Grade 8", section: "A", classroom: classroom)
        ].forEach { context.insert($0) }
        let exam = Exam(name: "Science Quiz", subject: "Science", classroom: classroom, numberOfQuestions: 20)
        let answerKey = AnswerKey(name: "Science Quiz Key", entries: Dictionary(uniqueKeysWithValues: (1...20).map { ($0, AnswerChoice.allCases[($0 - 1) % 5]) }))
        let template = ExamTemplate(name: "Science Answer Sheet", definition: SampleDataSeeder.template())
        exam.answerKey = answerKey
        exam.template = template
        context.insert(answerKey); context.insert(template); context.insert(exam)
        try? context.save()
    }

    static func template() -> TemplateDefinition {
        let choices = Array(AnswerChoice.allCases)
        let left = (1...17).map { question(number: $0, x: 0.29, y: 0.18 + Double($0 - 1) * 0.037, choices: choices) }
        let right = (18...20).map { question(number: $0, x: 0.56, y: 0.18 + Double($0 - 18) * 0.037, choices: choices) }
        let markers = [(0.20, 0.10), (0.49, 0.10), (0.78, 0.10), (0.20, 0.50), (0.78, 0.50), (0.20, 0.92), (0.49, 0.92), (0.78, 0.92)].map { MarkerDefinition(kind: .registration, expectedRect: NormalizedRect(x: $0.0, y: $0.1, width: 0.025, height: 0.018)) }
        let columns = (0..<9).map { NormalizedRect(x: 0.51 + Double($0) * 0.027, y: 0.60, width: 0.018, height: 0.018) }
        let rows = (0..<10).map { NormalizedRect(x: 0.51, y: 0.60 + Double($0) * 0.026, width: 0.018, height: 0.018) }
        return TemplateDefinition(pageAspectRatio: 0.707, questions: left + right,
                                  studentID: StudentIDDefinition(region: NormalizedRect(x: 0.48, y: 0.57, width: 0.28, height: 0.29), columns: columns, digitRows: rows, prefix: "320"),
                                  markers: markers, ignoredAreas: [], calibration: CalibrationProfile(), revision: 1)
    }

    private static func question(number: Int, x: Double, y: Double, choices: [AnswerChoice]) -> TemplateQuestionDefinition {
        TemplateQuestionDefinition(number: number, bubbles: choices.enumerated().map { index, choice in BubbleCoordinate(choice: choice, rect: NormalizedRect(x: x + Double(index) * 0.027, y: y, width: 0.019, height: 0.019)) })
    }
}