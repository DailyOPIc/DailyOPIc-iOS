import SwiftUI

/// 데일리 토큰 아트워크. Daily 토큰을 그림으로 보여주는 곳은 모두 이걸 쓴다.
///
/// 배경 원·그림자를 붙이지 않는다. 에셋 자체가 이미 3D 코인이라 뒤에 무언가를
/// 더 깔면 두 겹이 된다. 디테일이 많아 16pt 이하에서는 보라색 덩어리로 뭉치므로
/// 그런 자리에는 이미지 대신 글자만 쓴다(권장: 인라인 18 / 행·카드 20~24 / 설명 28~36).
struct DailyTokenIcon: View {
    var size: CGFloat = 20
    /// 옆에 "데일리 토큰"이라고 적혀 있으면 nil(장식). 아이콘만으로 뜻을 전할 때만 라벨을 준다.
    var accessibilityLabel: String?

    var body: some View {
        Image("ic_dailyopic_token")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(accessibilityLabel ?? "")
            .accessibilityHidden(accessibilityLabel == nil)
    }
}

#Preview("크기별") {
    HStack(spacing: 12) {
        ForEach([16, 20, 24, 32] as [CGFloat], id: \.self) { size in
            VStack {
                DailyTokenIcon(size: size)
                Text("\(Int(size))")
                    .font(.caption2)
            }
        }
    }
    .padding()
}
