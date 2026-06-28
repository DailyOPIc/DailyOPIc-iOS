import SwiftUI

struct DailyRefreshDialog: View {
    let isLoading: Bool
    let progressMessage: String?
    let select: (DifficultyAdjustment) -> Void
    let cancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.34)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isLoading { cancel() }
                }

            VStack(spacing: 18) {
                Image(systemName: "ticket.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                VStack(spacing: 8) {
                    Text("토큰 1개를 사용할까요?")
                        .font(.title3.bold())
                        .foregroundStyle(AppPalette.ink)
                    Text("새 Daily 문제를 불러오려면 토큰 1개가 소모됩니다. 원하는 난이도를 선택하면 바로 다음 문제 풀이를 이어갈 수 있습니다.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let progressMessage {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(AppPalette.primary)
                        Text(progressMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppPalette.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(AppPalette.primarySoft.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                ForEach(DifficultyAdjustment.allCases) { adjustment in
                    Button {
                        select(adjustment)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: iconName(for: adjustment))
                                .font(.headline)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(adjustment.title)
                                    .font(.headline)
                                Text(adjustment.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(AppPalette.secondaryInk)
                            }
                            Spacer()
                        }
                        .foregroundStyle(AppPalette.ink)
                        .padding(14)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }

                Button("취소", action: cancel)
                    .font(.headline)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .disabled(isLoading)
            }
            .padding(22)
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
