import SwiftUI

struct PracticeHistoryDetailView: View {
    let record: PracticeHistoryRecord

    var body: some View {
        ScrollView {
            if let evaluation = record.evaluation, let question = record.question {
                VStack(spacing: 20) {
                    QuestionCard(question: question, showsRubricFocus: false)
                    PracticeResultView(
                        evaluation: evaluation,
                        targetLevel: record.targetLevel,
                        transcript: record.transcript,
                        showsNextButton: false,
                        next: {}
                    )
                }
                .padding(.horizontal, 20)
            } else {
                ContentUnavailableView("기록을 읽을 수 없어요", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle("연습 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MockHistoryDetailView: View {
    let record: MockHistoryRecord

    var body: some View {
        Group {
            if let evaluation = record.evaluation {
                MockResultView(
                    evaluation: evaluation,
                    targetLevel: record.targetLevel,
                    showsResetButton: false,
                    reset: {}
                )
            } else {
                ContentUnavailableView("기록을 읽을 수 없어요", systemImage: "exclamationmark.triangle")
            }
        }
        .navigationTitle("모의고사 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}
