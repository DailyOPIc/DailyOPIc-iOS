import SwiftUI

struct OnboardingView: View {
    let preferences: AppPreferences
    @State private var step = 0
    @State private var selectedLevel: OPIcLevel = .IH
    @State private var profile = BackgroundProfile()

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [.white, AppPalette.primarySoft.opacity(0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if step == 0 {
                    levelSelection
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    backgroundSelection
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: step)
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("이전", systemImage: "chevron.left") { step = 0 }
                    }
                }
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
            Text("선택한 목표는 홈 화면에서 언제든 변경할 수 있어요.")
                .font(AppTypography.body)
                .foregroundStyle(AppPalette.secondaryInk)
                .multilineTextAlignment(.center)
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
            PrimaryButton(title: "설문 설정하기", systemImage: "arrow.right") {
                step = 1
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 20)
        }
    }

    private var backgroundSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text("나에게 맞는 문제를 준비할게요")
                    .font(AppTypography.title)
                Text("관심 있는 항목을 선택하면 AI가 설문형·돌발형 콤보에 반영합니다.")
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                Picker("직업", selection: optionalBinding(\.occupation)) {
                    Text("직업 선택 안 함").tag("")
                    ForEach(["office worker", "freelancer", "homemaker", "job seeker"], id: \.self) {
                        Text($0).tag($0)
                    }
                }
                .pickerStyle(.menu)
                .cardStyle()
                selectionGroup(title: "관심사", options: BackgroundProfile.interestOptions, values: $profile.interests)
                selectionGroup(title: "운동", options: BackgroundProfile.sportOptions, values: $profile.sports)
                selectionGroup(title: "여행", options: BackgroundProfile.travelOptions, values: $profile.travel)
                PrimaryButton(title: "DailyOPIc 시작", systemImage: "mic.fill") {
                    preferences.completeOnboarding(level: selectedLevel, profile: profile)
                }
            }
            .padding(24)
        }
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<BackgroundProfile, String?>) -> Binding<String> {
        Binding(
            get: { profile[keyPath: keyPath] ?? "" },
            set: { profile[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func selectionGroup(title: String, options: [String], values: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 105))], spacing: 10) {
                ForEach(options, id: \.self) { option in
                    let selected = values.wrappedValue.contains(option)
                    Button {
                        if selected {
                            values.wrappedValue.removeAll { $0 == option }
                        } else {
                            values.wrappedValue.append(option)
                        }
                    } label: {
                        Text(option)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(selected ? .white : AppPalette.primary)
                            .background(selected ? AppPalette.primary : .white)
                            .clipShape(Capsule())
                            .overlay { Capsule().stroke(AppPalette.primary.opacity(0.5)) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
