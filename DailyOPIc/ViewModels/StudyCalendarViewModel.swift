import Foundation
import Observation

/// 학습 캘린더의 I/O 담당. 파생 계산은 전부 `StudyCalendarSnapshot`(순수 함수)에 있다.
@MainActor
@Observable
final class StudyCalendarViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let environment: AppEnvironment
    private let api: APIClient
    private let preferences: AppPreferences

    var loadState: LoadState = .idle
    /// 진실은 서버지만, 마지막으로 성공한 설정을 로컬에 둬서 네트워크가 끊겨도
    /// 캘린더가 빈 화면이 되지 않게 한다.
    var settings: StudyPlanSettings?
    /// 서버 응답이 아니라 로컬 사본을 보여주는 중.
    var isShowingCachedSettings = false
    var isSaving = false
    var saveErrorMessage: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        api = environment.api
        preferences = environment.preferences
        settings = environment.preferences.studyPlanSettings
    }

    var isConfigured: Bool { settings != nil }

    /// 목표 등급은 캘린더가 따로 갖지 않는다. 기존 진실(AppPreferences/서버 프로필)을 읽기만 한다.
    var targetLevel: OPIcLevel { preferences.targetLevel ?? .IM2 }

    /// 하루 Daily 토큰 한도. 권장 학습량을 이 값으로 깎는다(한도지 숙제가 아니다).
    var dailyCapacity: Int {
        StudyPlanEstimator.dailyCapacity(
            capabilities: environment.capabilities,
            plan: environment.currentPlan
        )
    }

    var plan: PlanEntitlement { environment.currentPlan }

    var hasFailed: Bool {
        if case .failed = loadState { return true }
        return false
    }

    func loadIfNeeded() async {
        guard loadState == .idle || hasFailed else { return }
        await load()
    }

    func load() async {
        loadState = .loading
        do {
            let response = try await api.studyPlan()
            settings = response.configured ? response.studyPlan : nil
            preferences.studyPlanSettings = settings
            isShowingCachedSettings = false
            loadState = .loaded
        } catch {
            // 캐시가 있으면 캘린더는 계속 쓸 수 있다. 없으면 재시도 화면.
            settings = preferences.studyPlanSettings
            isShowingCachedSettings = settings != nil
            loadState = settings == nil ? .failed(error.localizedDescription) : .loaded
        }
    }

    /// 설정 저장(생성·수정 동일 경로). 성공해야 캘린더가 구성됨 상태가 된다.
    @discardableResult
    func save(_ draft: StudyPlanSettings) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        saveErrorMessage = nil
        defer { isSaving = false }
        do {
            let response = try await api.updateStudyPlan(draft, requestID: UUID())
            settings = response.studyPlan ?? draft
            preferences.studyPlanSettings = settings
            isShowingCachedSettings = false
            loadState = .loaded
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    func snapshot(completions: [Date: Int], recentLevel: OPIcLevel?) -> StudyCalendarSnapshot? {
        guard let settings else { return nil }
        return StudyCalendarSnapshot.make(
            settings: settings,
            targetLevel: targetLevel,
            recentLevel: recentLevel,
            dailyCapacity: dailyCapacity,
            completions: completions
        )
    }
}
