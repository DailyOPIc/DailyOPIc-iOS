import Foundation
import Observation

/// AI 맞춤 단어장 생성(P14.2)의 앱 쪽 진행 상태.
///
/// 과금 규칙은 P13 그대로다: **사용자 조작 1회 = 데일리 토큰 1개**. 강제는 서버가
/// 하고, 앱의 몫은 넷이다 — 누르기 전에 비용을 보여주고, 잔액이 0이면 요청을
/// 시작하지 않고, 서버가 거절하면 기존 부족 UX(광고 → 재시도 → 페이월)로 넘기고,
/// 잔액은 서버에서 다시 읽는다. 단어장 전용 화폐도, 두 번째 쿼터 체계도 없다.
///
/// 재시도는 **같은 조작**이다. `operationID`를 그대로 다시 보내야 서버가 이미 만든
/// 세트를 돌려주고 토큰이 또 나가지 않는다. 성공했을 때만 새 값으로 바뀐다.
@MainActor
@Observable
final class VocabularyGenerationViewModel {
    /// 한 세트의 값. 화면 문구와 서버 계약이 어긋나지 않게 여기 한 곳에 둔다.
    static let tokenCost = 1
    static let entryCount = 30

    private let environment: AppEnvironment
    private let api: APIClient
    private let ads: AdService
    private let persistence: PersistenceService

    var usage: UsageStatus?
    var operationState: AsyncOperationState = .idle
    var errorMessage: String?
    var showsPaywall = false
    private(set) var paywallSource: PaywallSource = .tokenExhausted
    /// 방금 만든 세트. 화면이 바로 열어 주기 위한 표식이고, 소비하면 비운다.
    var finishedSetID: String?

    private var operationID = UUID()
    private var task: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        api = environment.api
        ads = environment.ads
        persistence = environment.persistence
    }

    var dailyTokenCount: Int? { usage?.totalRemaining }
    var isGenerating: Bool { operationState.isRunning }
    /// 잔액을 아는데 0일 때만 참. 모를 때(nil)는 막지 않는다 — 최종 판단은 서버다.
    var hasNoTokens: Bool { dailyTokenCount == 0 }

    func refreshUsage() async {
        usage = try? await api.usage()
    }

    /// 화면이 CTA를 누른 자리. 이미 돌고 있으면 아무 일도 하지 않는다 —
    /// 연타가 두 번째 조작(=두 번째 차감)이 되지 않게 여기서 막는다.
    func generate(topic: VocabularyTopic, targetLevel: OPIcLevel, excluding terms: [String]) {
        guard !isGenerating else { return }
        errorMessage = nil
        task = Task { await run(topic: topic, targetLevel: targetLevel, excluding: terms) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        operationState = .idle
    }

    private func run(
        topic: VocabularyTopic,
        targetLevel: OPIcLevel,
        excluding terms: [String],
        allowRecovery: Bool = true
    ) async {
        // 잔액이 0이면 서버도 AI도 부르지 않는다. 먼저 토큰을 확보해야 시작한다.
        if hasNoTokens {
            guard allowRecovery, await recoverToken() else { return }
        }
        operationState = .running(operationId: operationID, startedAt: .now)
        let payload = VocabularyGenerationRequest(
            topic: topic,
            targetLevel: targetLevel,
            excludeTerms: Array(terms.prefix(VocabularyGenerationRequest.excludeLimit))
        )
        do {
            let set = try await api.generateVocabulary(request: payload, requestID: operationID)
            try persistence.saveVocabularyGeneratedSet(set)
            usage = try? await api.usage()
            // 저장까지 끝났을 때만 조작을 닫는다. 다음 생성은 새 조작이고 새 토큰이다.
            operationID = UUID()
            finishedSetID = set.setId
            operationState = .completed
        } catch is CancellationError {
            operationState = .idle
        } catch let error as APIClientError where error.isPracticeQuotaExhausted {
            // 서버와의 경합에서 졌다. 결과를 지어내지 않고 잔액을 다시 읽은 뒤 부족 UX로.
            usage = try? await api.usage()
            operationState = .idle
            // 복구는 한 번만 시도한다. 광고를 봐도 또 거절당하면 거기서 멈춘다.
            if allowRecovery, await recoverToken() {
                await run(
                    topic: topic,
                    targetLevel: targetLevel,
                    excluding: terms,
                    allowRecovery: false
                )
            }
        } catch let error as APIClientError where error.isAIUnavailable {
            // 서버가 이미 환불했다. 같은 조작 id로 다시 시도할 수 있다.
            usage = try? await api.usage()
            operationState = .recoverableFailure(
                operationId: operationID,
                message: "맞춤 단어를 만들지 못했어요. 잠시 후 다시 시도해 주세요."
            )
        } catch {
            usage = try? await api.usage()
            operationState = .recoverableFailure(
                operationId: operationID,
                message: error.localizedDescription
            )
        }
    }

    /// 토큰 부족 복구. 새 세트·분석이 쓰는 것과 같은 경로다:
    /// 무료는 광고 보너스 1개, 유료는 상위 플랜 안내. 자동 결제는 하지 않는다.
    private func recoverToken() async -> Bool {
        guard !environment.currentPlan.isPaid else {
            presentPaywall(from: .tokenExhausted)
            return false
        }
        do {
            let intent = try await api.createRewardIntent(
                purpose: .practiceCredits,
                requestID: UUID()
            )
            try await ads.showRewardedAd(
                userIdentifier: intent.userIdentifier,
                customData: intent.customData
            )
            _ = try await api.waitForReward(nonce: intent.nonce)
            usage = try await api.usage()
            return (dailyTokenCount ?? 0) > 0
        } catch is CancellationError {
            return false
        } catch let error as APIClientError
            where error.isPracticeQuotaExhausted || error.isRewardQuotaExhausted {
            presentPaywall(from: .tokenExhausted)
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func presentPaywall(from source: PaywallSource) {
        paywallSource = source
        showsPaywall = true
    }
}
