import SwiftUI

/// 플래너 홈의 "오늘의 OPIc TIP" 한 칸.
///
/// 하루에 하나, 누르는 곳도 없다(새로고침·즐겨찾기·공유 없음). 오늘의 학습 카드보다
/// 눈에 덜 띄어야 하므로 카드 테두리 대신 옅은 보라 배경에 여백도 한 단계 작게 쓴다.
struct OPIcTipCard: View {
    let tip: OPIcTip

    /// 아이콘은 장식이라 따로 읽지 않고, 제목과 본문을 한 문장으로 읽어 준다.
    var accessibilityText: String { "오늘의 OPIc 팁. \(tip.text)" }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: "lightbulb")
                .font(AppTypography.callout)
                .foregroundStyle(AppPalette.primary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("오늘의 OPIc TIP")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppPalette.secondaryInk)
                Text(tip.text)
                    .font(AppTypography.body)
                    // 팁은 줄여 쓰지 않는다. Dynamic Type을 키워도 전부 보여야 한다.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            AppPalette.primarySoft,
            in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}
