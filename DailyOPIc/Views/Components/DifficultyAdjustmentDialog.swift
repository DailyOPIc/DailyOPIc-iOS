import SwiftUI

struct DifficultyAdjustmentDialog: View {
    let isLoading: Bool
    let select: (DifficultyAdjustment) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                Image(systemName: "slider.horizontal.below.rectangle")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                Text("남은 문제 난이도를 골라주세요")
                    .font(.title3.bold())
                    .foregroundStyle(AppPalette.ink)
                Text("실제 시험처럼 앞 7문항 뒤에 난이도를 한 번 조정해요. 고른 난이도로 남은 문제가 만들어져요.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: AppSpacing.sm) {
                    ForEach(DifficultyAdjustment.allCases) { adjustment in
                        Button {
                            select(adjustment)
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: iconName(for: adjustment))
                                    .font(.headline)
                                    .foregroundStyle(AppPalette.primary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text(adjustment.title)
                                        .font(.headline)
                                        .foregroundStyle(AppPalette.ink)
                                    Text(adjustment.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(AppPalette.secondaryInk)
                                }
                                Spacer()
                            }
                            .padding(AppSpacing.md)
                            .background(AppPalette.elevatedSurface)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
                        }
                        .buttonStyle(PressableButtonStyle())
                        .disabled(isLoading)
                    }
                }

                if isLoading {
                    HStack(spacing: AppSpacing.sm) {
                        AppLoadingIndicator(dotSize: 7)
                        Text("남은 문제를 만들고 있어요")
                            .font(AppTypography.footnote)
                            .foregroundStyle(AppPalette.secondaryInk)
                    }
                }
            }
            .padding(AppSpacing.lg)
            .frame(maxWidth: 360)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.sheet, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
            .padding(AppSpacing.lg)
        }
        .transition(.opacity)
    }

    private func iconName(for adjustment: DifficultyAdjustment) -> String {
        switch adjustment {
        case .easier: "arrow.down.circle.fill"
        case .same: "equal.circle.fill"
        case .harder: "arrow.up.circle.fill"
        }
    }
}
