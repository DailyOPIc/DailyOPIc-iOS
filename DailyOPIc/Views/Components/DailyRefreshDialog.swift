import SwiftUI

/// 새 문제 받기 다이얼로그. 토큰 1개를 사용해 (1) 새 문제 받기 또는
/// (2) 난이도 재설정 후 새 문제 받기 중 선택한다. (광고/리워드 아님)
struct DailyRefreshDialog: View {
    let isLoading: Bool
    let progressMessage: String?
    let select: (DifficultyAdjustment) -> Void
    let cancel: () -> Void

    @State private var showsDifficulty = false

    /// 배경 탭과 이스케이프 제스처가 공유하는 단일 취소 경로. 로딩 중에는 닫지 않는다.
    private func dismiss() {
        if !isLoading { cancel() }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(spacing: AppSpacing.md) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                VStack(spacing: AppSpacing.sm) {
                    Text(showsDifficulty ? "난이도 재설정" : "새 문제 받기")
                        .font(.title3.bold())
                        .foregroundStyle(AppPalette.ink)
                    Text("토큰 1개를 사용해 새로운 문제 세트를 받아요.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let progressMessage {
                    HStack(spacing: AppSpacing.sm) {
                        AppLoadingIndicator(dotSize: 7)
                        Text(progressMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppPalette.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(AppSpacing.md)
                    .background(AppPalette.primarySoft.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                }

                if showsDifficulty {
                    // 난이도 선택: 더 쉽게 / 비슷하게 / 더 어렵게 (각각 토큰 1개).
                    ForEach(DifficultyAdjustment.allCases) { adjustment in
                        optionButton(
                            icon: iconName(for: adjustment),
                            title: adjustment.title,
                            subtitle: adjustment.subtitle
                        ) { select(adjustment) }
                    }
                } else {
                    optionButton(
                        icon: "arrow.clockwise.circle.fill",
                        title: "새 문제 받기",
                        subtitle: "지금과 비슷한 난이도의 새 문제"
                    ) { select(.same) }
                    optionButton(
                        icon: "slider.horizontal.3",
                        title: "난이도 재설정",
                        subtitle: "더 쉽게 / 더 어렵게 골라서 받기"
                    ) { showsDifficulty = true }
                }

                Button(showsDifficulty ? "뒤로" : "취소") {
                    if showsDifficulty { showsDifficulty = false } else { cancel() }
                }
                .font(.headline)
                .foregroundStyle(AppPalette.secondaryInk)
                .minimumTouchTarget()
                .disabled(isLoading)
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: 360)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .padding(AppSpacing.lg)
            // 배경 탭과 같은 취소 경로를 VoiceOver 이스케이프 제스처에도 열어준다.
            .accessibilityAction(.escape, dismiss)
        }
        .transition(.opacity)
    }

    private func optionButton(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.headline)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(title).font(.headline)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppPalette.secondaryInk)
                }
                Spacer()
            }
            .foregroundStyle(AppPalette.ink)
            .padding(AppSpacing.md)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func iconName(for adjustment: DifficultyAdjustment) -> String {
        switch adjustment {
        case .easier: "arrow.down.circle.fill"
        case .same: "equal.circle.fill"
        case .harder: "arrow.up.circle.fill"
        }
    }
}
