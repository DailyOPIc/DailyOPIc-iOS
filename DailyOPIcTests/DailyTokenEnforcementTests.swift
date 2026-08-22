import Foundation
import Testing
@testable import DailyOPIc

/// P13 — 사용자가 시작한 AI 작업은 무료가 아니다.
///
/// 계약: 새 Daily 세트 1개 = 데일리 토큰 1개, AI 분석 1회 = 데일리 토큰 1개(추가).
/// 강제는 서버가 한다. 앱이 지켜야 할 몫은 (1) 누르기 전에 비용을 말하고,
/// (2) 토큰이 없으면 요청을 시작하지 않고, (3) 서버가 거절하면 기존 부족 UX로
/// 넘기고, (4) 잔액을 서버 기준으로 다시 읽는 것이다. 여기서 그 넷을 고정한다.
///
/// `AppEnvironment.api`는 프로토콜이 아니라 구체 `actor APIClient`라 가짜 서버를
/// 주입할 수 없다. 그래서 뷰모델 배선은 이 저장소가 이미 쓰는 방식(소스 계약 검사,
/// `PaywallTests.runtimeSourceHasNoHardcodedWonPrice` 참고)으로 고정한다.
struct DailyTokenEnforcementTests {
    // MARK: - 런타임 계약

    /// CTA에 뜨는 숫자의 출처. 무료분과 광고 보너스는 같은 지갑이다.
    @Test func dailyTokenCountAddsFreeAndBonusRemaining() {
        let usage = UsageStatus(
            date: "20260820",
            freeRemaining: 1,
            bonusRemaining: 1,
            serverDateKey: "20260820",
            resetsAt: nil,
            dailyAnalysisFreeRemaining: nil,
            dailyAnalysisRewardRemaining: nil,
            dailyRefreshRemaining: nil,
            mockAvailable: nil,
            mockRemaining: nil,
            mockSessionStage: nil
        )
        #expect(usage.totalRemaining == 2)
    }

    /// 토큰 부족은 일반 서버 오류가 아니다. 이 판별이 무너지면 사용자는
    /// "알 수 없는 오류"를 보고 왜 막혔는지 알 수 없게 된다.
    @Test func serverTokenRejectionIsRecognizedAsItsOwnCase() {
        let exhausted = APIClientError.server(
            status: 402,
            code: "practice_quota_exhausted",
            message: "daily practice quota exhausted"
        )
        #expect(exhausted.isPracticeQuotaExhausted)

        let generic = APIClientError.server(status: 500, code: nil, message: "boom")
        #expect(!generic.isPracticeQuotaExhausted)
    }

    // MARK: - 소스 계약

    private func source(_ relativePath: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
            .appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func runtimeSources() -> [URL] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
        return FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
    }

    /// A·J. 분석 CTA는 누르기 전에 "토큰 1개"라고 말한다. 재분석도 같은 패널을
    /// 지나므로 의도적으로 다시 분석할 때마다 같은 비용이 다시 보인다.
    @Test func analysisCallToActionAdvertisesOneToken() throws {
        let panel = try source("Views/Components/TranscriptReviewPanel.swift")
        #expect(panel.contains("데일리 토큰 \\(tokenCost)개를 사용해요"))

        let screen = try source("Views/Screens/Main/Practice/PracticeScreen.swift")
        #expect(screen.contains("tokenCost: 1"))
        // 분석을 시작하는 경로는 이 패널 하나뿐이다.
        #expect(screen.components(separatedBy: "analyzePendingRecording()").count - 1 == 1)
    }

    /// B. 토큰 그림은 정식 아이콘 하나뿐이다. 분석용 토큰 아이콘을 새로 만들지 않는다.
    @Test func onlyTheCanonicalTokenIconExists() throws {
        #expect(try source("Views/Components/TranscriptReviewPanel.swift").contains("DailyTokenIcon"))
        for url in runtimeSources() where url.lastPathComponent != "DailyTokenIcon.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("Image(\"ic_"), "\(url.lastPathComponent)가 별도 토큰 아트워크를 쓴다")
        }
    }

    /// C·D. 토큰이 0이면 분석 요청 자체가 시작되지 않는다(제공자 호출 전에 멈춘다).
    /// 잔액을 모를 때(usage == nil)는 막지 않는다 — 최종 판단은 서버다.
    @Test func zeroTokensStopTheAnalysisBeforeItStarts() throws {
        let viewModel = try source("ViewModels/PracticeViewModel.swift")
        let guardIndex = try #require(viewModel.range(of: "if dailyTokenCount == 0"))
        let analyzingIndex = try #require(
            viewModel.range(of: "phase = .analyzing", range: guardIndex.upperBound..<viewModel.endIndex)
        )
        #expect(guardIndex.upperBound < analyzingIndex.lowerBound)
        #expect(viewModel.contains("guard unlocked else { return }"))
    }

    /// E. 부족 UX는 새로 만들지 않는다. 새 세트가 쓰던 광고 → 재시도 → 페이월을
    /// 그대로 재사용한다(두 번째 쿼터 체계를 만들지 않는다).
    @Test func insufficientTokenReusesTheExistingRewardAndPaywallFlow() throws {
        let viewModel = try source("ViewModels/PracticeViewModel.swift")
        let recovery = try #require(viewModel.range(of: "private func recoverAnalysisToken"))
        let body = String(viewModel[recovery.lowerBound...].prefix(1200))
        #expect(body.contains("unlockPracticeCredits()"))
        #expect(body.contains("presentPaywall(from: .tokenExhausted)"))
        // 자동 결제는 없다. 결제는 페이월에서 사용자가 직접 한다.
        #expect(!body.contains("purchase("))
    }

    /// F. 서버와의 경합에서 지면(402) 결과를 지어내지 않고, 잔액을 다시 읽고,
    /// 일반 오류가 아니라 부족 UX로 넘긴다.
    @Test func backendTokenRejectionRefreshesUsageAndShowsTheQuotaUX() throws {
        let viewModel = try source("ViewModels/PracticeViewModel.swift")
        let clause = try #require(
            viewModel.range(of: "catch let error as APIClientError where error.isPracticeQuotaExhausted")
        )
        let body = String(viewModel[clause.lowerBound...].prefix(700))
        #expect(body.contains("usage = try? await api.usage()"))
        #expect(body.contains("recoverAnalysisToken()"))
    }

    /// G·H. 성공한 분석도, 실패해서 서버가 환불한 분석도 잔액을 서버에서 다시 읽는다.
    /// 실패 뒤 토큰이 하나 줄어든 채로 화면에 남지 않는다.
    @Test func usageRefreshesAfterBothSuccessAndFailure() throws {
        let viewModel = try source("ViewModels/PracticeViewModel.swift")
        let evaluate = try #require(viewModel.range(of: "private func evaluatePendingRecording"))
        let body = String(viewModel[evaluate.lowerBound...].prefix(4000))
        #expect(body.components(separatedBy: "usage = try? await api.usage()").count - 1 >= 3)
    }

    /// I. 이미 나온 결과를 다시 보는 것은 무료다. 결과 화면에 비용 문구가 없고
    /// 결과 화면에서 과금 API를 부르지 않는다.
    @Test func viewingAnExistingResultCostsNothing() throws {
        let result = try source("Views/Screens/Main/Practice/PracticeResultView.swift")
        #expect(!result.contains("토큰"))
        #expect(!result.contains("evaluatePractice"))
    }

    /// §27. 새 세트 CTA는 그대로 토큰 1개다(획득 동작을 바꾸지 않았다).
    @Test func newSetDialogStillAdvertisesExactlyOneToken() throws {
        let dialog = try source("Views/Components/DailyRefreshDialog.swift")
        #expect(dialog.contains("DailyTokenIcon"))
        #expect(dialog.contains("토큰 1개를 사용해 새로운 문제 세트를 받아요."))
    }

    /// §27. 분석 과금이 세트 획득을 이중으로 청구하지 않는다.
    /// 분석 경로는 세트 생성/리프레시 API를 부르지 않는다.
    @Test func analysisNeverTriggersSetAcquisition() throws {
        let viewModel = try source("ViewModels/PracticeViewModel.swift")
        let evaluate = try #require(viewModel.range(of: "private func evaluatePendingRecording"))
        let body = String(viewModel[evaluate.lowerBound...].prefix(4000))
        #expect(!body.contains("refreshPracticeSet"))
        #expect(!body.contains("createPracticeSet"))
    }

    /// §27. 플래너·하루 시트·학습한 문항·시험 가이드는 AI를 부르지 않으므로
    /// 토큰도 쓰지 않는다. 휴식일 Daily 흐름도 같은 화면·같은 규칙을 쓴다.
    @Test func plannerAndGuideSurfacesNeverSpendTokens() throws {
        let billing = ["evaluatePractice", "refreshPracticeSet", "createPracticeSet", "DailyTokenIcon"]
        let surfaces = [
            "Views/Screens/Main/Calendar/PlannerHomeView.swift",
            "Views/Screens/Main/Calendar/PlannerDaySheet.swift",
            "Views/Screens/Main/Calendar/PlannerFullCalendarView.swift",
            "Views/Screens/Onboarding/OPIcGuideView.swift",
        ]
        for surface in surfaces {
            let text = try source(surface)
            for symbol in billing {
                #expect(!text.contains(symbol), "\(surface)가 \(symbol)을 쓴다")
            }
        }
    }

    /// §19·§37. 폐기된 약속이 앱 어디에도 남아 있지 않다.
    /// "분석은 무료 / 세트 내 평가 무제한 / 토큰은 새 문제를 받을 때만"은 이제 거짓이다.
    @Test func noSourceStillPromisesFreeAnalysis() throws {
        let obsolete = [
            "추가 토큰이 들지 않",
            "평가는 무제한",
            "분석은 무료",
            "평가는 무료",
            "무제한 재평가",
            "새 문제를 받을 때만",
        ]
        for url in runtimeSources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            for phrase in obsolete {
                #expect(!text.contains(phrase), "\(url.lastPathComponent)에 폐기된 문구 '\(phrase)'가 있다")
            }
        }
    }

    /// 사용자에게 보이는 화폐 이름은 "데일리 토큰" 하나다.
    /// OpenAI 토큰(모델 입출력 단위)은 제품 화폐가 아니므로 노출하지 않는다.
    @Test func userFacingCopyNeverMentionsProviderTokens() throws {
        for url in runtimeSources() {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("OpenAI 토큰"), "\(url.lastPathComponent)")
            #expect(!text.contains("GPT 토큰"), "\(url.lastPathComponent)")
        }
    }
}
