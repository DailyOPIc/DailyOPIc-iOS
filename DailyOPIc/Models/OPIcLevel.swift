import Foundation

enum OPIcLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case NL, NM, NH, IL, IM1, IM2, IM3, IH, AL

    var id: String { rawValue }

    var description: String {
        switch self {
        case .NL: "단어 위주로 의사 표현을 시작하는 단계"
        case .NM: "짧은 문장으로 기본 응답이 가능한 단계"
        case .NH: "간단한 설명과 묘사가 가능한 단계"
        case .IL: "기본적인 일상 대화를 짧게 이어가는 단계"
        case .IM1: "친숙한 주제를 중심으로 간단히 설명하는 단계"
        case .IM2: "경험을 구체적으로 묘사하고 이어가는 단계"
        case .IM3: "다양한 상황을 비교·설명하는 단계"
        case .IH: "생각과 이유를 논리적으로 상세히 전달하는 단계"
        case .AL: "폭넓은 주제를 자연스럽고 설득력 있게 다루는 단계"
        }
    }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum SelfAssessmentLevel: Int, Codable, CaseIterable, Identifiable, Sendable {
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4
    case level5 = 5
    case level6 = 6

    var id: Int { rawValue }
    var title: String { "\(rawValue)단계" }

    var estimatedRange: String {
        switch self {
        case .level1: "예상 IL"
        case .level2: "예상 IL ~ IM1"
        case .level3: "예상 IM1"
        case .level4: "예상 IM1 ~ IM2"
        case .level5: "예상 IM2 ~ IH"
        case .level6: "예상 IH ~ AL"
        }
    }

    var summary: String {
        switch self {
        case .level1: "단순 묘사와 현재 시제 중심의 매우 짧은 답변"
        case .level2: "간단한 루틴과 짧은 경험 설명"
        case .level3: "일상 주제에서 경험과 이유 설명 시작"
        case .level4: "경험, 이유, 간단한 비교와 변화 설명"
        case .level5: "경험, 비교, 변화, 롤플레이를 포함하는 실전 표준 난이도"
        case .level6: "복합 경험, 문제 해결, 추상 의견과 사회적 영향 분석"
        }
    }

    var expectedTargetLevel: OPIcLevel {
        switch self {
        case .level1: .IL
        case .level2, .level3: .IM1
        case .level4: .IM2
        case .level5: .IH
        case .level6: .AL
        }
    }

    static func from(targetLevel: OPIcLevel?) -> SelfAssessmentLevel? {
        switch targetLevel {
        case .NL, .NM, .NH, .IL: .level1
        case .IM1: .level3
        case .IM2, .IM3: .level4
        case .IH: .level5
        case .AL: .level6
        case nil: nil
        }
    }
}

enum DifficultyAdjustment: String, Codable, CaseIterable, Identifiable, Sendable {
    case easier
    case same
    case harder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .easier: "더 쉬운 질문"
        case .same: "비슷한 질문"
        case .harder: "더 어려운 질문"
        }
    }

    var subtitle: String {
        switch self {
        case .easier: "후반 문제를 한 단계 낮춰 진행합니다."
        case .same: "현재 난이도를 유지합니다."
        case .harder: "후반 문제를 한 단계 높여 진행합니다."
        }
    }
}
