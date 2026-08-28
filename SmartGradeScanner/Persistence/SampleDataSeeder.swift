import Foundation
import SwiftData

enum SampleDataSeeder {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        upgradeBundledTemplateIfNeeded(in: context)
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
        let answerKey = AnswerKey(name: "Science Quiz Key",
                                  entries: Dictionary(uniqueKeysWithValues: (1...20).map { ($0, AnswerChoice.allCases[($0 - 1) % 5]) }))
        let template = ExamTemplate(name: "Science Answer Sheet", definition: SampleDataSeeder.template())
        exam.answerKey = answerKey
        exam.template = template
        context.insert(answerKey)
        context.insert(template)
        context.insert(exam)
        try? context.save()
    }


    @MainActor
    private static func upgradeBundledTemplateIfNeeded(in context: ModelContext) {
        let descriptor = FetchDescriptor<ExamTemplate>()
        guard let templates = try? context.fetch(descriptor) else { return }
        var changed = false
        for storedTemplate in templates where storedTemplate.name == "Science Answer Sheet" && storedTemplate.definition.revision < 3 {
            storedTemplate.definition = template()
            changed = true
        }
        if changed { try? context.save() }
    }

    // Calibrated from the supplied reference answer sheet itself. Coordinates use a
    // top-left origin and are normalized to the detected page, not to the camera frame.
    static func template() -> TemplateDefinition {
        let choices = Array(AnswerChoice.allCases)
        let bubbleWidth = 0.0203
        let bubbleHeight = 0.0232
        let leftX = [0.2919, 0.3164, 0.3418, 0.3672, 0.3917]
        let rightX = [0.4475, 0.4712, 0.4975, 0.5220, 0.5465]
        let rowY = [
            0.2104, 0.2471, 0.2857, 0.3243, 0.3610, 0.4015, 0.4392,
            0.5386, 0.5753, 0.6149, 0.6506, 0.6882, 0.7259, 0.7645,
            0.8031, 0.8417, 0.8803
        ]

        let leftQuestions = (1...17).map { number in
            question(number: number,
                     xStarts: leftX,
                     y: rowY[number - 1],
                     width: bubbleWidth,
                     height: bubbleHeight,
                     choices: choices)
        }
        let rightQuestions = (18...20).map { number in
            question(number: number,
                     xStarts: rightX,
                     y: rowY[number - 18],
                     width: bubbleWidth,
                     height: bubbleHeight,
                     choices: choices)
        }

        let markers: [MarkerDefinition] = [
            marker(centerX: 0.2327, centerY: 0.1400, width: 0.0186, height: 0.0212),
            marker(centerX: 0.4873, centerY: 0.1873, width: 0.0135, height: 0.0154),
            marker(centerX: 0.7411, centerY: 0.1400, width: 0.0170, height: 0.0212),
            marker(centerX: 0.2327, centerY: 0.5415, width: 0.0186, height: 0.0212),
            marker(centerX: 0.4873, centerY: 0.5135, width: 0.0135, height: 0.0154),
            marker(centerX: 0.7411, centerY: 0.5415, width: 0.0170, height: 0.0212),
            marker(centerX: 0.2327, centerY: 0.9421, width: 0.0186, height: 0.0193),
            marker(centerX: 0.4873, centerY: 0.9469, width: 0.0135, height: 0.0135),
            marker(centerX: 0.7411, centerY: 0.9421, width: 0.0170, height: 0.0193)
        ]

        let columnsX = [0.4882, 0.5127, 0.5381, 0.5635, 0.5888, 0.6125, 0.6387, 0.6641, 0.6887]
        let rowsY = [0.5927, 0.6274, 0.6622, 0.6969, 0.7326, 0.7664, 0.8012, 0.8340, 0.8687, 0.9025]
        let columns = columnsX.map {
            NormalizedRect(x: $0, y: rowsY[0], width: bubbleWidth, height: bubbleHeight)
        }
        let rows = rowsY.map {
            NormalizedRect(x: columnsX[0], y: $0, width: bubbleWidth, height: bubbleHeight)
        }

        var calibration = CalibrationProfile()
        calibration.minimumMarkerCount = 5
        calibration.markerReprojectionTolerance = 0.025

        return TemplateDefinition(
            pageAspectRatio: 591.0 / 518.0,
            questions: leftQuestions + rightQuestions,
            studentID: StudentIDDefinition(
                region: NormalizedRect(x: 0.475, y: 0.570, width: 0.245, height: 0.370),
                columns: columns,
                digitRows: rows,
                prefix: "320"
            ),
            markers: markers,
            ignoredAreas: [],
            calibration: calibration,
            revision: 3
        )
    }


    // Portrait five-question sheet used by the in-app test/reference image.
    // Coordinates were measured directly from the 1086 x 1448 reference sheet.
    // This profile intentionally uses the six large square registration marks only;
    // the small black bars beside the ID instructions are row guides, not alignment marks.
    static func portraitFiveQuestionTemplate() -> TemplateDefinition {
        let choices = Array(AnswerChoice.allCases)
        let bubbleWidth = 0.03499
        let bubbleHeight = 0.02693
        let xStarts = [0.31031, 0.36464, 0.41989, 0.47514, 0.53039]
        let rowY = [0.22997, 0.27210, 0.31423, 0.35635, 0.39779]

        let questions = (1...5).map { number in
            question(number: number,
                     xStarts: xStarts,
                     y: rowY[number - 1],
                     width: bubbleWidth,
                     height: bubbleHeight,
                     choices: choices)
        }

        let markers: [MarkerDefinition] = [
            MarkerDefinition(kind: .registration, expectedRect: NormalizedRect(x: 0.22007, y: 0.09945, width: 0.02486, height: 0.01934)),
            MarkerDefinition(kind: .registration, expectedRect: NormalizedRect(x: 0.77901, y: 0.09945, width: 0.02486, height: 0.01934)),
            MarkerDefinition(kind: .registration, expectedRect: NormalizedRect(x: 0.22007, y: 0.46961, width: 0.02486, height: 0.01934)),
            MarkerDefinition(kind: .registration, expectedRect: NormalizedRect(x: 0.74494, y: 0.46961, width: 0.02578, height: 0.01934)),
            MarkerDefinition(kind: .registration, expectedRect: NormalizedRect(x: 0.22007, y: 0.91022, width: 0.02486, height: 0.01934)),
            MarkerDefinition(kind: .registration, expectedRect: NormalizedRect(x: 0.74494, y: 0.91022, width: 0.02578, height: 0.01934))
        ]

        let columnsX = [0.31492, 0.35451, 0.39411, 0.43278, 0.47330, 0.51381, 0.55341, 0.59300, 0.63352]
        let rowsY = [0.55118, 0.58625, 0.62155, 0.65539, 0.68984, 0.72376, 0.75691, 0.79006, 0.82320, 0.85543]
        let idBubbleWidth = 0.03131
        let idBubbleHeight = 0.02348
        let columns = columnsX.map {
            NormalizedRect(x: $0, y: rowsY[0], width: idBubbleWidth, height: idBubbleHeight)
        }
        let rows = rowsY.map {
            NormalizedRect(x: columnsX[0], y: $0, width: idBubbleWidth, height: idBubbleHeight)
        }

        var calibration = CalibrationProfile()
        calibration.minimumMarkerCount = 4
        calibration.markerReprojectionTolerance = 0.035
        calibration.minimumLocalContrast = 0.045

        return TemplateDefinition(
            pageAspectRatio: 0.75,
            questions: questions,
            studentID: StudentIDDefinition(
                region: NormalizedRect(x: 0.30018, y: 0.48757, width: 0.36464, height: 0.39296),
                columns: columns,
                digitRows: rows,
                prefix: "320"
            ),
            markers: markers,
            ignoredAreas: [],
            calibration: calibration,
            revision: 4
        )
    }

    private static func question(number: Int,
                                 xStarts: [Double],
                                 y: Double,
                                 width: Double,
                                 height: Double,
                                 choices: [AnswerChoice]) -> TemplateQuestionDefinition {
        TemplateQuestionDefinition(number: number,
                                   bubbles: zip(xStarts, choices).map { x, choice in
                                       BubbleCoordinate(choice: choice,
                                                        rect: NormalizedRect(x: x,
                                                                             y: y,
                                                                             width: width,
                                                                             height: height))
                                   })
    }

    private static func marker(centerX: Double,
                               centerY: Double,
                               width: Double,
                               height: Double) -> MarkerDefinition {
        MarkerDefinition(kind: .registration,
                         expectedRect: NormalizedRect(x: centerX - width / 2,
                                                      y: centerY - height / 2,
                                                      width: width,
                                                      height: height))
    }
}
