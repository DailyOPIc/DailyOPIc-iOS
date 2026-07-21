import SwiftUI

struct OPIcGuideView: View {
    let preferences: AppPreferences
    let completion: (_ skipped: Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Int

    private let pages: [GuidePage] = [
        .init(
            icon: "sparkles",
            title: "DailyOPIc는 AI 학습 도구예요",
            body: "영어 말하기를 꾸준히 연습하고 피드백을 받도록 돕습니다. 공식 OPIc 시험이나 공식 등급 판정 서비스는 아닙니다."
        ),
        .init(
            icon: "text.bubble.fill",
            title: "여러 질문 유형을 연습해요",
            body: "묘사, 일상 루틴, 과거 경험, 비교, 롤플레이, 문제 해결, 의견 질문을 실제 답변 흐름에 맞춰 연습합니다."
        ),
        .init(
            icon: "slider.horizontal.3",
            title: "시작 난이도는 1~6단계예요",
            body: "처음 고른 단계로 학습을 시작하고, 모의고사 Q7 뒤에는 더 쉽게·비슷하게·더 어렵게 중 하나를 한 번 선택합니다."
        ),
        .init(
            icon: "list.clipboard.fill",
            title: "Background Survey로 개인화해요",
            body: "현재 상태, 거주 형태, 취미와 관심사를 바탕으로 질문 주제를 구성합니다. 언제든 학습 설정에서 바꿀 수 있습니다."
        ),
        .init(
            icon: "mic.fill",
            title: "Daily에서 짧게 반복해요",
            body: "영어 답변을 녹음하면 실시간 transcript를 확인하고 AI 분석을 받을 수 있습니다. 분석 횟수와 광고로 받는 새 질문 횟수는 별도입니다."
        ),
        .init(
            icon: "checklist",
            title: "모의고사는 15문항이에요",
            body: "하루 한 번, Q1~Q7과 Q8~Q15로 진행합니다. 시작·난이도 조정·최종 분석에 총 3회의 보상형 광고가 필요하며 중단해도 이어할 수 있습니다."
        ),
        .init(
            icon: "lock.shield.fill",
            title: "결과와 개인정보를 확인하세요",
            body: "결과는 실제 시험과 다를 수 있습니다. 마이크와 transcript는 분석에 사용되며, 모의고사 오디오는 기기에 임시 보관한 뒤 완료·포기 시 삭제합니다. 가이드는 설정에서 다시 볼 수 있습니다."
        )
    ]

    init(preferences: AppPreferences, completion: @escaping (Bool) -> Void) {
        self.preferences = preferences
        self.completion = completion
        _page = State(initialValue: preferences.lastGuidePage)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ProgressView(value: Double(page + 1), total: Double(pages.count))
                    .accessibilityLabel("가이드 진행률")
                    .accessibilityValue("\(page + 1) / \(pages.count)")
                Spacer(minLength: 12)
                let content = pages[page]
                Image(systemName: content.icon)
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                    .accessibilityHidden(true)
                Text(content.title)
                    .font(AppTypography.title)
                    .multilineTextAlignment(.center)
                Text(content.body)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .cardStyle()
                Spacer()
                HStack(spacing: 12) {
                    if page > 0 {
                        Button("이전") { move(to: page - 1) }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    PrimaryButton(
                        title: page == pages.count - 1 ? "가이드 완료" : "다음",
                        systemImage: page == pages.count - 1 ? "checkmark" : "arrow.right"
                    ) {
                        if page == pages.count - 1 {
                            preferences.lastGuidePage = 0
                            completion(false)
                        } else {
                            move(to: page + 1)
                        }
                    }
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("건너뛰기") {
                        preferences.lastGuidePage = page
                        completion(true)
                    }
                }
            }
        }
    }

    private func move(to value: Int) {
        let change = { page = value; preferences.lastGuidePage = value }
        if reduceMotion { change() }
        else { withAnimation(.easeInOut(duration: 0.2)) { change() } }
    }
}

private struct GuidePage {
    let icon: String
    let title: String
    let body: String
}
