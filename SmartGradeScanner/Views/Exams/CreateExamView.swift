import SwiftUI
import SwiftData

struct CreateExamView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var classrooms: [Classroom]
    @State private var name = ""
    @State private var subject = ""
    @State private var count = 20
    @State private var selectedClassroomID: UUID?
    var body: some View {
        NavigationStack { Form {
            Section("Exam details") { TextField("Exam name", text: $name); TextField("Subject", text: $subject); Stepper("Questions: \(count)", value: $count, in: 1...200) }
            Section("Class") { Picker("Classroom", selection: $selectedClassroomID) { Text("None").tag(nil as UUID?); ForEach(classrooms) { Text($0.name).tag($0.id as UUID?) } } }
            Section { Button("Create Exam") { let classroom = classrooms.first { $0.id == selectedClassroomID }; let exam = Exam(name: name.isEmpty ? "Untitled Exam" : name, subject: subject.isEmpty ? "General" : subject, classroom: classroom, numberOfQuestions: count); context.insert(exam); try? context.save(); dismiss() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.navigationTitle("New Exam").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }
    }
}