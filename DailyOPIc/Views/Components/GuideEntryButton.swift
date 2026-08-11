import SwiftUI

/// 도움말 진입 버튼. 여는 방식은 호출자가 정한다. 메인 탭에서는 탭 위에 덮는
/// fullScreenCover를, 온보딩 안에서는 자기 단계 전환을 쓰기 때문이다.
struct GuideEntryButton: View {
    let open: () -> Void

    var body: some View {
        Button {
            open()
        } label: {
            Label("도움말", systemImage: "questionmark.circle")
        }
        .accessibilityHint("데일리오픽 사용법과 오픽 시험 안내를 엽니다")
    }
}
