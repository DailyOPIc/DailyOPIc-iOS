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
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppPalette.primary)
                VStack(spacing: 8) {
                    Text("광고 보고 새 질문 받기")
                        .font(.title3.bold())
                        .foregroundStyle(AppPalette.ink)
                    Text("새 질문은 데일리 토큰을 쓰지 않아요. 광고를 끝까지 보면 원하는 난이도의 새 질문을 받아요.")
                        .font(AppTypography.body)
                        .foregroundStyle(AppPalette.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let progressMessage {
                    HStack(spacing: 10) {
                        AppLoadingIndicator(dotSize: 7)
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
