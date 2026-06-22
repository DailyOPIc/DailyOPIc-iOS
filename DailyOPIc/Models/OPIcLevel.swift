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
