import SwiftUI

struct QuestionCard: View {
    let question: GeneratedQuestion
    var showsNumber = false
    var showsRubricFocus = true
    @State private var showsHint = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                if showsNumber {
                    Text("QUESTION \(question.number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppPalette.primary)
                }
                Spacer()
                Text(question.questionType?.label ?? question.type.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppPalette.secondaryInk)
            }
            Text(question.prompt)
                .font(AppTypography.cardTitle)
                .foregroundStyle(AppPalette.ink)
                .fixedSize(horizontal: false, vertical: true)
            hintSection
            if showsRubricFocus {
                FlowTags(values: Array(question.rubricFocus.prefix(3)))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.primarySoft)
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppPalette.primary.opacity(0.55), lineWidth: 1.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onChange(of: question.id) {
            showsHint = false
        }
    }

    private var hintSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) { showsHint.toggle() }
            } label: {
                Label(showsHint ? "힌트 접기" : "힌트 보기", systemImage: showsHint ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.primary)
            }
            .buttonStyle(.plain)

            if showsHint {
                Text(hintText)
                    .font(AppTypography.body)
                    .foregroundStyle(AppPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private var hintText: String {
        switch question.questionType {
        case .description:
            "대상, 장소, 분위기, 특징을 2~3가지로 나눠서 말해보세요."
        case .routine:
            "평소 하는 순서, 빈도, 함께 하는 사람을 넣어 자연스럽게 답해보세요."
        case .pastExperience:
            "언제, 어디서, 누구와, 무슨 일이 있었는지 시간 순서대로 말해보세요."
        case .comparison:
            "두 대상이나 과거와 현재를 비교하고, 차이가 생긴 이유를 덧붙여보세요."
        case .roleplay:
            "상대에게 먼저 묻고, 필요한 정보와 요청을 구체적으로 말해보세요."
        case .problemSolving:
            "문제 상황, 해결 방법, 대안, 마무리 요청을 차례로 구성해보세요."
        case .opinion:
            "내 의견을 먼저 말하고, 이유와 예시를 하나씩 덧붙여보세요."
        case nil:
            "핵심 경험 하나를 고르고, 이유와 예시를 함께 말해보세요."
        }
    }
}
