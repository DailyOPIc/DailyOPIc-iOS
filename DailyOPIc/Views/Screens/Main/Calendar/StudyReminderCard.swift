import SwiftUI

/// 학습 알림 한 칸. 플래너 안에서 알림 이야기를 하는 곳은 여기뿐이다.
/// 카드마다 알림 배지를 붙이지 않고, 유료 잠금과도 섞지 않는다(모든 플랜이 쓴다).
struct StudyReminderCard: View {
    let service: StudyReminderService
    /// 알림 시각은 학습 설정의 "공부 시간" 하나뿐이다. 별도 알림 시각 필드를 두지 않는다.
    let studyTime: StudyTimeOfDay
    /// 시간을 고치러 갈 곳. 공부 시간 피커가 이미 같은 화면에 있으면 nil(버튼을 감춘다).
    var onEditPlan: (() -> Void)?
    let onReconcile: () -> Void

    @State private var isConfirmingEnable = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("학습 알림")
                .font(AppTypography.sectionTitle)
            if service.needsSystemPermission {
                deniedContent
            } else if service.isActive {
                enabledContent
            } else {
                disabledContent
            }
        }
        .cardStyle()
        .alert("공부할 시간에 알려드릴까요?", isPresented: $isConfirmingEnable) {
            // 시스템 권한 창은 오직 이 버튼에서만 뜬다.
            Button("알림 켜기") {
                Task {
                    await service.enable()
                    onReconcile()
                }
            }
            Button("나중에", role: .cancel) {}
        } message: {
            Text(
                "설정한 학습 시간에 오늘 계획을 한 번 알려드려요.\n"
                + "오늘 계획을 미리 완료했다면 남은 알림은 보내지 않아요."
            )
        }
    }

    // MARK: 상태별 본문

    private var disabledContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("설정한 공부 시간에 오늘 계획을 한 번 알려드려요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("학습 알림 켜기") { isConfirmingEnable = true }
                .font(AppTypography.callout)
                .minimumTouchTarget()
        }
    }

    private var enabledContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // 상태를 색이 아니라 기호+문구로 알린다.
            Label("매일 \(studyTime.displayText) · 학습일에만", systemImage: "bell.fill")
                .font(AppTypography.body)
                .accessibilityLabel("학습 알림 켜짐, 학습일 \(studyTime.displayText)")
            HStack(spacing: AppSpacing.md) {
                if let onEditPlan {
                    Button("시간 변경", action: onEditPlan)
                        .minimumTouchTarget()
                }
                Button("알림 끄기") {
                    Task { await service.disable() }
                }
                .minimumTouchTarget()
            }
            .font(AppTypography.callout)
        }
    }

    private var deniedContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Label("알림이 꺼져 있어요.", systemImage: "bell.slash.fill")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
            Text("iPhone 설정에서 알림을 허용하면 다시 알려드릴 수 있어요.")
                .font(AppTypography.footnote)
                .foregroundStyle(AppPalette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppSpacing.md) {
                Button("설정에서 알림 허용") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .minimumTouchTarget()
                Button("알림 끄기") {
                    Task { await service.disable() }
                }
                .minimumTouchTarget()
            }
            .font(AppTypography.callout)
        }
    }
}
