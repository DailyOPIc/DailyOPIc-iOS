import SwiftUI

struct DifficultyAdjustmentDialog: View {
    let isLoading: Bool
    let select: (DifficultyAdjustment) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "slider.horizontal.below.rectangle")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                Text("후반 난이도를 선택하세요")
                    .font(.title3.bold())
                    .foregroundStyle(AppPalette.ink)
                Text("실제 OPIc처럼 전반 7문항 이후 난이도를 다시 조정합니다. 선택한 난이도에 맞춰 남은 문제가 생성됩니다.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    ForEach(DifficultyAdjustment.allCases) { adjustment in
                        Button {
                            select(adjustment)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: iconName(for: adjustment))
                                    .font(.headline)
                                    .foregroundStyle(AppPalette.primary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(adjustment.title)
                                        .font(.headline)
                                        .foregroundStyle(AppPalette.ink)
                                    Text(adjustment.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(AppPalette.secondaryInk)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                }

                if isLoading {
                    ProgressView("남은 문제를 생성하는 중입니다.")
                        .font(.footnote)
                }
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            }
            .padding(24)
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
