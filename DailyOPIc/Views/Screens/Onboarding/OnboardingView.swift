import SwiftUI

struct OnboardingView: View {
    let preferences: AppPreferences
    @State private var selectedLevel: OPIcLevel = .IH

    init(preferences: AppPreferences) {
        self.preferences = preferences
        _selectedLevel = State(initialValue: preferences.targetLevel ?? .IH)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.white, AppPalette.primarySoft.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                levelSelection
            }
        }
    }

    private var levelSelection: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 32)
            Text("목표 오픽 등급을 선택하세요")
                .font(AppTypography.title)
                .multilineTextAlignment(.center)
                .foregroundStyle(AppPalette.ink)
            Text("선택한 목표 등급을 바탕으로 데일리 문제가 준비됩니다.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            TabView(selection: $selectedLevel) {
                ForEach(OPIcLevel.allCases) { level in
                    VStack(spacing: 26) {
                        Text(level.rawValue)
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(AppPalette.primary)
                        Text(level.description)
                            .font(.title3)
                            .foregroundStyle(AppPalette.primary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                        Text(level == selectedLevel ? "선택됨" : "선택")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(AppPalette.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    }
                    .padding(30)
                    .background(AppPalette.primarySoft)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(AppPalette.primary.opacity(0.7), lineWidth: 1.5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .padding(.horizontal, 28)
                    .tag(level)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 430)
            PrimaryButton(title: "DailyOPIc 시작", systemImage: "mic.fill") {
                preferences.completeOnboarding(level: selectedLevel, profile: BackgroundProfile())
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 20)
        }
    }
}
