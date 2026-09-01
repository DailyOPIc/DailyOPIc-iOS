import Foundation

enum AsyncOperationKind: String, Sendable {
    case questionGeneration
    case speechAnalysis
    case mockResult
    case difficultyAdjustment
    case vocabularyGeneration
    case vocabularyCoach
    case dataLoading
    case retry

    var title: String {
        switch self {
        case .questionGeneration: "질문을 준비하고 있어요"
        case .speechAnalysis: "답변을 분석하고 있어요"
        case .mockResult: "모의고사 결과를 만들고 있어요"
        case .difficultyAdjustment: "난이도를 조정하고 있어요"
        case .vocabularyGeneration: "단어 \(VocabularyDailySet.dailyTarget)개를 만들고 있어요"
        case .vocabularyCoach: "표현을 자연스럽게 썼는지 확인하고 있어요"
        case .dataLoading: "학습 정보를 불러오고 있어요"
        case .retry: "처리 상태를 확인하고 있어요"
        }
    }
}

enum AsyncOperationState: Equatable, Sendable {
    case idle
    case running(operationId: UUID, startedAt: Date)
    case recoverableFailure(operationId: UUID, message: String)
    case terminalFailure(message: String)
    case completed

    var isRunning: Bool {
        if case .running = self { true } else { false }
    }
}
