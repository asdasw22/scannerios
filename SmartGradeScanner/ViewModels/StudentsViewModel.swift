import Foundation
import SwiftData

@MainActor final class StudentsViewModel: ObservableObject {
    func delete(_ student: Student, from context: ModelContext) { context.delete(student); try? context.save() }
}