import Foundation
import Testing
@testable import DailyOPIc

/// 단어장 UI/UX 정리(P14.6.1). 두 가지만 본다 —
/// (1) "추가 학습 / 20개 더 학습하기"라는 제품 표현이 사라졌는지,
/// (2) 오늘의 단어 카드가 진행·완료·다음 걸음을 실제로 그리는지.
///
/// 과금 경계는 여기서 건드리지 않는다. 그건 `VocabularyExtraTests`와
/// `DailyTokenEnforcementTests`의 몫이고, 문구를 고쳤다고 약해지면 안 된다.
@MainActor
struct VocabularyPolishTests {
    // MARK: 도우미

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 주석을 뺀 코드만. 사라져야 하는 것은 화면에 찍히는 말이지 설명이 아니다.
    private func code(_ file: String) -> String {
        file
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func homeBody(_ screen: String) throws -> String {
        let start = try #require(screen.range(of: "private var home: some View"))
        let end = try #require(screen.range(of: "private func destination("))
        return String(screen[start.lowerBound..<end.lowerBound])
    }

    private let viewDirectory = "Views/Screens/Main/Vocabulary/"
    private let screenPath = "Views/Screens/Main/Vocabulary/VocabularyScreen.swift"
    private let studyPath = "Views/Screens/Main/Vocabulary/VocabularyStudyView.swift"
    private let extraPath = "Views/Screens/Main/Vocabulary/VocabularyExtraViews.swift"
    private let listPath = "Views/Screens/Main/Vocabulary/VocabularyListViews.swift"

    /// 사용자가 실제로 닿는 단어장 화면들. 도달 경로가 없는 파일은 여기 없다.
    private var reachableViews: [String] {
        [
            "VocabularyScreen.swift",
            "VocabularyStudyView.swift",
            "VocabularyExtraViews.swift",
            "VocabularyListViews.swift",
            "VocabularySpeakingCoachViews.swift"
        ]
    }

    // MARK: 1. 사라진 말

    /// "추가"라는 말은 제품에서 없앤다. 사용자에게 이건 곁다리가 아니라
    /// 그냥 새로 만드는 단어다 — 이름이 곁다리면 가치도 곁다리로 읽힌다.
    @Test func theRemovedProductLanguageIsGone() throws {
        let banned = [
            "오늘 20개 더 학습하기",
            "추가 학습",
            "오늘 추가 학습",
            "추가 20개",
            "Extra 20",
            "더 공부하기",
            "더 공부할까요",
            // P14.6.1 §20: 입구 문구는 하나뿐이다.
            "AI 맞춤 단어장",
            "30개 만들기",
            // P14.6.1 FIX §10: "새로운 단어"라는 별도 제품 이름을 없앤다.
            // 사용자는 base/generated를 구분할 필요가 없다 — 전부 오늘의 단어다.
            "새로운 단어"
        ]
        for file in reachableViews {
            let body = code(try source(viewDirectory + file))
            for phrase in banned {
                #expect(!body.contains(phrase), "\(file)에 \"\(phrase)\"가 남아 있다")
            }
        }
    }

    /// 예전 30개 시트는 파일째 사라졌다(P14.6.2). 열 방법이 없던 화면을 남겨 두면
    /// 다음 사람이 그 문구를 다시 살린다.
    @Test func theOldThirtySetSheetIsGone() throws {
        for file in reachableViews {
            let body = code(try source(viewDirectory + file))
            #expect(!body.contains("VocabularyGenerationSheet("))
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc/Views/Screens/Main/Vocabulary")
            .appendingPathComponent("VocabularyGenerationViews.swift")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    // MARK: 2. 남은 말

    /// 생성 입구는 하나뿐이고, 그 하나가 개수와 값을 함께 말한다.
    /// 누르기 전에 얼마인지 모르는 자리는 없다(§4).
    @Test func theOnlyCreateEntryPointStatesCountAndPrice() throws {
        #expect(VocabularyGenerationViewModel.extraEntryCount == 20)
        #expect(VocabularyGenerationViewModel.tokenCost == 1)
        #expect(VocabularyCreateButton.title == "단어 20개 만들기")

        let extra = code(try source(extraPath))
        #expect(extra.contains("struct VocabularyCreateButton"))
        #expect(extra.contains("DailyTokenIcon(size: 18)"))
        #expect(extra.contains("데일리 토큰 \\(VocabularyGenerationViewModel.tokenCost)개 사용"))
        // 채움 버튼이 아니다 — 가장 큰 버튼 자리는 공짜 학습에 남겨 둔다(§8).
        #expect(!extra.contains("PrimaryButton(title: Self.title"))
        #expect(extra.contains("AppPalette.primarySoft"))
    }

    /// 시트가 묻는 말과 확인 문구. 주제를 고르는 것만으로는 아무 일도 하지 않는다.
    @Test func theSheetAsksThenConfirms() throws {
        let sheet = code(try source(extraPath))
        #expect(sheet.contains("어떤 주제로 만들까요?"))
        #expect(sheet.contains("\\(topic.label) 단어 \\(count)개를 만들까요?"))
        #expect(sheet.contains("데일리 토큰 \\(VocabularyGenerationViewModel.tokenCost)개를 사용해요."))
        // 주제 버튼이 하는 일은 고르는 것뿐이다.
        #expect(sheet.contains("Button { topic = candidate }"))
        #expect(sheet.components(separatedBy: "viewModel.generate(").count - 1 == 1)
    }

    // MARK: 3. 오늘의 단어 카드

    /// 하루의 상태는 셋뿐이고, 각 상태가 홈에서 실제로 그려진다.
    @Test func theTodayCardDrawsAllThreeStates() throws {
        let screen = code(try source(screenPath))
        let home = try homeBody(screen)
        #expect(home.contains("todayCard"))
        #expect(screen.contains("if todaySet == nil {"))
        #expect(screen.contains("오늘의 단어"))
        // 아직 안 고른 날: 묻는 것은 주제뿐이다.
        #expect(screen.contains("오늘은 어떤 주제로"))
        #expect(screen.contains("주제 선택하기"))
        // 하는 중: 숫자 + 막대 + 남은 개수.
        #expect(screen.contains("countLine(todayStudiedCount, of: todayEntries.count)"))
        #expect(screen.contains("progressBar(todayStudiedCount, of: todayEntries.count)"))
        #expect(screen.contains("이어 학습하기"))
        // 다 한 날: 가득 찬 막대 + 완료 표시.
        #expect(screen.contains("completionBadge(\"오늘 학습 완료\")"))
    }

    /// 진행은 숫자와 막대 둘 다로 말한다. 완료는 체크 하나로 끝낸다 —
    /// 폭죽도, 계속 움직이는 화면도 없다(§8).
    @Test func progressIsDrawnCalmly() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("ProgressView(value: Double(done), total: Double(max(total, 1)))"))
        #expect(screen.contains("Image(systemName: \"checkmark.circle.fill\")")
            || screen.contains("systemImage: \"checkmark.circle.fill\""))
        #expect(!screen.contains("confetti"))
        #expect(!screen.contains(".repeatForever"))
    }

    /// 오늘 몫을 끝내면 두 가지가 보인다 — 방금 배운 것 다시 보기, 그리고
    /// 새로 만들기. 만들지 않아도 완료 표시는 그대로 남는다(§25).
    @Test func theFinishedDayOffersLearnedWordsAndCreation() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("NavigationLink(value: VocabularyRoute.todayLearned)"))
        #expect(screen.contains("오늘 학습한 단어 보기"))
        #expect(screen.contains("VocabularyCreateButton { isShowingExtraSheet = true }"))
        // 완료 표시는 새 단어 여부와 무관한 가지에서 그려진다.
        let complete = try #require(screen.range(of: "private var todayComplete"))
        let section = try #require(screen.range(of: "private var newWordsSection"))
        #expect(complete.lowerBound < section.lowerBound)
    }

    /// 만든 단어의 진행도는 오늘의 20개와 **다른 줄**이다.
    /// 만든 단어를 학습한다고 오늘의 단어가 20/20에서 되돌아가지 않는다(§22).
    @Test func createdWordsHaveTheirOwnProgressLine() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("만든 단어 \\(extraStudiedCount) / \\(extraEntries.count)"))
        #expect(screen.contains("progressBar(extraStudiedCount, of: extraEntries.count)"))
        // 두 진행도가 같은 값을 쓰지 않는다.
        #expect(screen.contains("todayStudiedCount"))
        #expect(screen.contains("extraStudiedCount"))
    }

    /// 이어 하기는 오늘의 단어 카드 안의 두 번째 줄이다. 제 이름을 가진 별도 구역이
    /// 아니고, 진행도가 곧 안내 문구다(P14.6.1 FIX §12).
    @Test func resumingIsASecondaryLineNotAProductName() throws {
        let screen = code(try source(screenPath))
        #expect(screen.contains("\\(extraStudiedCount) / \\(extraEntries.count) 이어 학습하기"))
        #expect(screen.contains("\"만든 단어 학습\""))
        // 세트 id로 정확히 그 세트를 연다 — 아무 세트나 이어 하지 않는다.
        #expect(screen.contains("VocabularyRoute.generatedStudy(setID: set.setID)"))
        #expect(screen.contains("todayExtraSets.first"))
    }

    /// 만들고 나서 축하 화면을 한 장 더 세우지 않는다. 시트가 닫히면 곧바로
    /// 기존 학습 화면이다(§11).
    @Test func creationGoesStraightIntoStudy() throws {
        let screen = code(try source(screenPath))
        let sheet = code(try source(extraPath))
        #expect(sheet.contains("onCreated?(setID)"))
        #expect(screen.contains("onCreated: { pendingCreatedSetID = $0 }"))
        #expect(screen.contains(".navigationDestination(item: $createdSetID)"))
        #expect(screen.contains("destination(.generatedStudy(setID: setID))"))
    }

    /// 만든 세트의 학습 화면도 이름이 "오늘의 단어"다 — 완료도 체크 한 줄로 끝난다.
    @Test func theCreatedSetStudiesUnderTheTodayName() throws {
        #expect(VocabularyStudyKind.aiSet.title == "오늘의 단어")
        #expect(VocabularyStudyKind.aiSet.completionTitle == "학습 완료")
        #expect(VocabularyStudyKind.aiSet.completionMessage(count: 20)
            == "20개의 단어와 표현을 학습했어요.")
    }

    // MARK: 4. 학습 화면

    /// 카드 위에서도 얼마나 왔는지 보인다. 다시 나온 카드는 진행도를 되돌리지 않는다.
    @Test func theStudyScreenShowsHowFarYouAre() throws {
        let study = code(try source(studyPath))
        #expect(study.contains("Text(\"\\(session.attemptedCount) / \\(plannedCount)\")"))
        #expect(study.contains("value: Double(session.attemptedCount)"))
        #expect(study.contains("\\(plannedCount)개 중 \\(session.attemptedCount)개 완료"))
    }

    /// 같은 카드를 두 번 답해도 진행도는 한 번만 오른다.
    @Test func aRetriedCardIsCountedOnce() {
        let entries = Array(VocabularyCatalog.all.prefix(2))
        var session = VocabularyStudySession(entries: entries)
        session.answer(knewIt: false)          // 첫 장 — 틀려서 뒤로 간다
        #expect(session.attemptedCount == 1)
        session.answer(knewIt: true)           // 둘째 장
        #expect(session.attemptedCount == 2)
        session.answer(knewIt: true)           // 다시 나온 첫 장
        #expect(session.attemptedCount == 2)
        #expect(session.isFinished)
        #expect(session.knownCount == 1)
        #expect(session.forgottenCount == 1)
    }

    /// 저장은 학습과 다른 채널이다. 새 햅틱 관리자를 만들지 않고
    /// 앱이 이미 쓰는 `sensoryFeedback` 하나만 쓴다(§12).
    @Test func savingIsItsOwnChannel() throws {
        let study = code(try source(studyPath))
        #expect(study.contains("persistence.setVocabularySaved(entryID: entry.id, isSaved: !saved)"))
        #expect(study.contains(".sensoryFeedback(.selection, trigger: saveFeedback)"))
        #expect(!study.contains("HapticManager"))
        // 저장 버튼이 학습 기록을 건드리지 않는다.
        let button = try #require(study.range(of: "private func saveButton"))
        let next = try #require(study.range(of: "private func pronunciationButton"))
        let body = String(study[button.lowerBound..<next.lowerBound])
        #expect(!body.contains("recordVocabularyAnswer"))
        #expect(!body.contains("nextReviewLocalDate"))
    }

    // MARK: 5. 읽히는 화면

    /// 진행도·값·저장 상태는 그림만이 아니라 말로도 전해진다.
    @Test func theScreenSpeaksItsState() throws {
        let screen = code(try source(screenPath))
        let study = code(try source(studyPath))
        let extra = code(try source(extraPath))
        let list = code(try source(listPath))
        #expect(screen.contains("accessibilityLabel(\"\\(total)개 중 \\(done)개 완료\")"))
        #expect(study.contains(".accessibilityValue(saved ? \"저장됨\" : \"저장 안 됨\")"))
        #expect(extra.contains(".accessibilityAddTraits(candidate == topic ? [.isSelected] : [])"))
        #expect(list.contains("accessibilityLabel(\"저장함\")"))
    }

    /// 큰 글자에서 문구가 잘리지 않게 고정 높이를 쓰지 않는다(§26).
    @Test func nothingIsPinnedToAFixedHeight() throws {
        for file in [screenPath, studyPath, extraPath, listPath] {
            let body = code(try source(file))
            #expect(!body.contains(".frame(height: 54)"))
            #expect(!body.contains(".frame(height: 56)"))
        }
    }
}
