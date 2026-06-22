import SwiftUI

struct SetupView: View {
    let preferences: AppPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var level: OPIcLevel

    init(preferences: AppPreferences) {
        self.preferences = preferences
        _level = State(initialValue: preferences.targetLevel ?? .IH)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("목표 등급") {
                    Picker("목표 등급", selection: $level) {
                        ForEach(OPIcLevel.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Text(level.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("앱") {
                    Button("온보딩 다시 보기") {
                        preferences.resetOnboarding()
                        dismiss()
                    }
                }
            }
            .navigationTitle("학습 설정")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        preferences.targetLevel = level
                        dismiss()
                    }
                }
            }
        }
    }
}
