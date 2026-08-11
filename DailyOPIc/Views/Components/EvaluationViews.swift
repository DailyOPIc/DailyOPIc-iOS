import SwiftUI

struct LevelResultCard: View {
    let predicted: OPIcLevel
    let target: OPIcLevel
    let confidence: ConfidenceBand
    /// 결과가 완전하지 않다고 서버가 알려준 경우(resultStatus == "partial").
    var isPartial = false
    /// The grade is the hero element of this card, so it stays larger than any
    /// text style while still scaling with Dynamic Type via UIFontMetrics.
    @ScaledMetric(relativeTo: .largeTitle) private var gradeSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("OPIc 예상 등급")
                .font(.headline)
            HStack(alignment: .firstTextBaseline) {
                Text(predicted.rawValue)
                    .font(.system(size: gradeSize, weight: .bold, design: .rounded))
                    // 접근성 큰 글씨에서 등급 한 글자가 카드를 다 먹지 않도록.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer()
                Text("목표 \(target.rawValue)")
                    .font(.subheadline.weight(.semibold))
            }
            // 확신을 광고하지 않는다. 근거가 약할 때만 그 사실을 말한다.
            if let caution {
                Label(caution, systemImage: "exclamationmark.circle.fill")
                    .font(AppTypography.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("AI 예상 등급이라 실제 시험 결과와 다를 수 있어요.")
                .font(AppTypography.footnote)
                .opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppPalette.actionOnPrimary)
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.primary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        // 등급·목표·주의를 한 덩어리로 읽어준다.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var caution: String? {
        if isPartial {
            return "결과 일부를 준비하지 못했어요. 예상 등급은 참고로만 봐주세요."
        }
        return confidence.cautionMessage
    }

    private var accessibilityText: String {
        var text = "OPIc 예상 등급 \(predicted.rawValue), 목표 \(target.rawValue)."
        if let caution { text += " \(caution)" }
        return text + " AI 예상 등급이라 실제 시험 결과와 다를 수 있어요."
    }
}

struct RubricBandsView: View {
    let rubrics: [RubricAssessment]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("항목별 피드백").font(.headline)
            ForEach(rubrics) { rubric in
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(rubric.dimension.label).font(.subheadline.bold())
                        Spacer()
                        // 밴드는 색이 아니라 기호+문구로 구분한다.
                        Label(rubric.band.label, systemImage: rubric.band.icon)
                            .font(.caption.bold())
                            .foregroundStyle(AppPalette.primary)
                            .padding(.horizontal, AppSpacing.sm)
                            .padding(.vertical, AppSpacing.xs)
                            .background(AppPalette.primarySoft)
                            .clipShape(Capsule())
                    }
                    Text(rubric.evidence)
                        .font(AppTypography.body)
                        .fixedSize(horizontal: false, vertical: true)
                    // 다음 답변에서 무엇을 할지가 이 화면의 핵심이라 작은 회색 글씨로 두지 않는다.
                    Label(rubric.nextAction, systemImage: "arrow.right.circle.fill")
                        .font(AppTypography.callout.weight(.semibold))
                        .foregroundStyle(AppPalette.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(rubric.dimension.label), \(rubric.band.label). \(rubric.evidence) 다음 행동, \(rubric.nextAction)"
                )
                if rubric.id != rubrics.last?.id { Divider() }
            }
        }
        .cardStyle()
    }
}

struct FeedbackSection: View {
    let title: String
    private let items: [String]
    var tint = AppPalette.primarySoft

    /// Single free-text block.
    init(title: String, text: String, tint: Color = AppPalette.primarySoft) {
        self.title = title
        self.items = [text]
        self.tint = tint
    }

    /// Bulleted list; each entry gets its own leading bullet (fixes the
    /// previous "\n• " join that dropped the first item's bullet).
    init(title: String, bullets: [String], tint: Color = AppPalette.primarySoft) {
        self.title = title
        self.items = bullets
        self.tint = tint
    }

    /// 내용이 없으면 섹션 자체를 그리지 않는다. 빈 제목 카드나 가짜 자리표시자를
    /// 만들지 않으려고 호출부마다 검사하는 대신 여기 한 곳에서 막는다.
    private var visibleItems: [String] {
        items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        if !visibleItems.isEmpty { section }
    }

    private var section: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppPalette.primary)
            if visibleItems.count > 1 {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.sm) {
                            Text("•")
                            Text(item)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            } else {
                Text(visibleItems.first ?? "")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}

/// 모의고사 문항별 피드백. 서버는 이미 문항마다 피드백과 예시 답변을 주는데
/// 화면에는 한 번도 그려지지 않고 있었다. 접어 두고 필요할 때 펼치게 한다.
struct PerQuestionFeedbackView: View {
    let items: [PerQuestionFeedback]

    var body: some View {
        if !items.isEmpty {
            DisclosureGroup("문항별 피드백 \(items.count)개") {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            Text("\(item.number)번 문항")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppPalette.primary)
                            Text(item.feedback)
                                .font(AppTypography.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                            if !item.sampleAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                FeedbackSection(
                                    title: "예시 답변",
                                    text: item.sampleAnswer,
                                    tint: AppPalette.successSoft
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if item.id != items.last?.id { Divider() }
                    }
                }
                .padding(.top, AppSpacing.md)
            }
            .cardStyle()
        }
    }
}

extension View {
    func cardStyle(alignment: Alignment = .leading) -> some View {
        padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: alignment)
            .background(.background)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(AppPalette.primary.opacity(0.22), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }
}

/// 결과 분석 화면의 플랜별 잠금 해제 사다리.
/// 무료=예상등급+강점, 베이직=+개선점·루브릭, 플러스=+목표갭·교정·모범.
/// `showsPerQuestion`(프로)은 어디에서도 쓰이지 않아 "프로면 문항별 피드백"이라는
/// 사실이 아닌 약속만 남기고 있었으므로 삭제했다. 문항별 피드백은 잠금 없이 보여준다.
struct ResultUnlock {
    let plan: PlanEntitlement

    var showsImprovements: Bool { plan >= .basic }
    var showsRubrics: Bool { plan >= .basic }
    var showsTargetGap: Bool { plan >= .plus }
    var showsCorrectionAndSample: Bool { plan >= .plus }
}

/// 유료 잠금 섹션. 탭하면 페이월을 연다.
struct LockedFeedbackSection: View {
    let title: String
    let requiredPlan: PlanEntitlement
    let onUpgrade: () -> Void

    var body: some View {
        Button(action: onUpgrade) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "lock.fill")
                        .font(.subheadline)
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text("\(requiredPlan.displayName)에서 잠금 해제")
                        .font(AppTypography.caption.weight(.semibold))
                }
                .foregroundStyle(AppPalette.primary)
                Text("업그레이드하면 이 항목을 볼 수 있어요.")
                    .font(AppTypography.footnote)
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppPalette.primarySoft.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .stroke(AppPalette.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .buttonStyle(.plain)
    }
}
