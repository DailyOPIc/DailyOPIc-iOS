import SwiftUI

/// Guide hub. Splits into two separate documents:
/// 1) what DailyOPIc is (service intro), and
/// 2) what the OPIc exam is (for people new to the test).
struct OPIcGuideView: View {
    let preferences: AppPreferences
    let completion: (_ skipped: Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    Text("무엇이 궁금하세요?")
                        .font(AppTypography.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, AppSpacing.sm)

                    ForEach(GuideTopic.allCases) { topic in
                        NavigationLink {
                            GuideReaderView(topic: topic) { completion(false) }
                        } label: {
                            GuideTopicCard(topic: topic)
                        }
                        .buttonStyle(.plain)
                    }

                    PrimaryButton(title: "바로 시작하기", systemImage: "arrow.right") {
                        completion(false)
                    }
                    .padding(.top, AppSpacing.sm)
                }
                .padding(AppSpacing.lg)
            }
            .background(AppPalette.surface.opacity(0.5).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("닫기") { completion(true) }
                }
            }
        }
    }
}

// MARK: - Topics

enum GuideTopic: String, CaseIterable, Identifiable {
    case service
    case exam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .service: "데일리오픽이 뭔가요?"
        case .exam: "오픽 시험이 궁금해요"
        }
    }

    var subtitle: String {
        switch self {
        case .service: "이 앱을 어떻게 쓰는지 알려드려요"
        case .exam: "오픽 시험이 처음이라면 여기부터"
        }
    }

    var icon: String {
        switch self {
        case .service: "sparkles"
        case .exam: "questionmark.circle.fill"
        }
    }

    var pages: [GuidePage] {
        switch self {
        case .service:
            [
                .init(icon: "sparkles", title: "매일 영어 말하기 연습",
                      body: "데일리오픽은 AI와 함께 영어 말하기를 연습하는 앱이에요. 공식 오픽 시험이나 등급 판정 서비스는 아니에요."),
                .init(icon: "mic.fill", title: "듣고, 말하고, 분석받기",
                      body: "질문을 듣고 영어로 답하면 AI가 분석해줘요. 데일리에서 짧게 자주 연습해 보세요."),
                .init(icon: "checklist", title: "모의고사로 실전 연습",
                      body: "하루 한 번, 15문항으로 실제 시험처럼 연습할 수 있어요. 중간에 멈춰도 오늘 안엔 이어서 할 수 있어요."),
                .init(icon: "lock.shield.fill", title: "결과는 참고용이에요",
                      body: "분석 결과는 실제 시험과 다를 수 있어요. 녹음한 답변은 분석에만 쓰이고 끝나면 지워져요.")
            ]
        case .exam:
            [
                .init(icon: "questionmark.circle.fill", title: "오픽(OPIc)이란?",
                      body: "컴퓨터로 보는 영어 말하기 시험이에요. 화면에서 나오는 질문을 듣고 마이크에 영어로 답하면 돼요."),
                .init(icon: "list.clipboard.fill", title: "나에 맞춘 질문",
                      body: "시험 전에 관심사 설문을 해요. 내가 고른 주제(취미, 여행 등)를 바탕으로 질문이 나와요."),
                .init(icon: "text.bubble.fill", title: "이런 질문이 나와요",
                      body: "묘사, 일상, 과거 경험, 비교, 역할극, 문제 해결처럼 다양한 유형을 말로 답해요."),
                .init(icon: "chart.bar.fill", title: "등급은 이렇게",
                      body: "NL(초급)부터 AL(최상급)까지 있어요. 많은 분들이 IM~IH 등급을 목표로 해요."),
                .init(icon: "hand.thumbsup.fill", title: "가장 중요한 건",
                      body: "완벽한 정답보다, 자연스럽게 이어서 말하는 게 중요해요. 편하게 연습해 보세요.")
            ]
        }
    }
}

struct GuidePage {
    let icon: String
    let title: String
    let body: String
}

// MARK: - Hub card

private struct GuideTopicCard: View {
    let topic: GuideTopic

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: topic.icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(AppPalette.primary)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(topic.title)
                    .font(AppTypography.cardTitle)
                    .foregroundStyle(AppPalette.ink)
                Text(topic.subtitle)
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .foregroundStyle(AppPalette.secondaryInk)
        }
        .padding(AppSpacing.lg)
        .background(AppPalette.elevatedSurface)
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .stroke(AppPalette.primary.opacity(0.22), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
    }
}

// MARK: - Paged reader

private struct GuideReaderView: View {
    let topic: GuideTopic
    let onFinish: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private var pages: [GuidePage] { topic.pages }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            ProgressView(value: Double(page + 1), total: Double(pages.count))
                .tint(AppPalette.primary)
                .accessibilityLabel("진행률")
                .accessibilityValue("\(page + 1) / \(pages.count)")

            Spacer(minLength: 12)
            let content = pages[page]
            Image(systemName: content.icon)
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(AppPalette.primary)
                .accessibilityHidden(true)
                .id(page)
                .transition(.scale.combined(with: .opacity))
            Text(content.title)
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
            Text(content.body)
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .cardStyle(alignment: .center)
            Spacer()

            HStack(spacing: 12) {
                if page > 0 {
                    Button("이전") { move(to: page - 1) }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                PrimaryButton(
                    title: page == pages.count - 1 ? "다 봤어요" : "다음",
                    systemImage: page == pages.count - 1 ? "checkmark" : "arrow.right"
                ) {
                    if page == pages.count - 1 { dismiss() }
                    else { move(to: page + 1) }
                }
            }
        }
        .padding(AppSpacing.lg)
        .navigationTitle(topic.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func move(to value: Int) {
        if reduceMotion { page = value }
        else { withAnimation(.easeInOut(duration: 0.25)) { page = value } }
    }
}
