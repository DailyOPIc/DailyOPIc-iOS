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
    private let persistence: PersistenceService

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
        persistence = environment.persistence
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

    /// 캘린더 자동화 권한. 화면과 planner는 플랜을 직접 보지 않고 이 값만 본다.
    var featurePolicy: CalendarFeaturePolicy {
        CalendarFeaturePolicy.resolve(
            capabilities: environment.capabilities,
            plan: environment.currentPlan
        )
    }

    /// 이 플랜에서 아직 잠겨 있는 캘린더 기능(화면 노출 순서 그대로).
    var lockedFeatures: [CalendarLockedFeature] {
        CalendarLockedFeature.allCases.filter { $0.isLocked(under: featurePolicy) }
    }

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
        // 설정을 바꾸기 전에 지금 설정 기준의 과거를 봉인한다.
        // 이걸 빼먹으면 캘린더를 열지 않은 날들이 나중에 "새 설정"으로 되살아난다.
        if let current = settings { sealHistory(using: current) }
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

    /// 오늘까지의 배정 학습량을 고정한다. 지난 날짜는 이미 기록이 있으면 건드리지 않는다.
    /// 실패해도 캘린더는 계속 보여준다(다음 실행에서 다시 시도).
    func freezeSchedule(_ snapshot: StudyCalendarSnapshot, today: Date = .now) {
        guard let settings else { return }
        try? persistence.freezeStudyDayPlans(
            snapshot.targetsToFreeze(settings: settings, today: today),
            today: LocalCalendarDate.text(from: today, timeZone: settings.timeZone)
        )
    }

    /// 지금 설정 기준으로 계획 시작일~오늘의 배정 학습량을 고정한다.
    /// 완료 기록이 필요 없다(배정량은 완료와 무관하다) → 캘린더 화면 없이도 호출할 수 있다.
    func sealHistory(using settings: StudyPlanSettings, today: Date = .now) {
        let base = StudyPlanEstimator.effectiveDailyTarget(
            intensity: settings.intensity,
            dailyCapacity: dailyCapacity
        )
        try? persistence.freezeStudyDayPlans(
            AdaptiveStudyPlanner.historicalTargets(
                settings: settings,
                baseDailyTarget: base,
                today: today
            ),
            today: LocalCalendarDate.text(from: today, timeZone: settings.timeZone)
        )
    }

    func snapshot(
        completions: [Date: Int],
        recentLevel: OPIcLevel?,
        historicalTargets: [String: Int]
    ) -> StudyCalendarSnapshot? {
        guard let settings else { return nil }
        return StudyCalendarSnapshot.make(
            settings: settings,
            targetLevel: targetLevel,
            recentLevel: recentLevel,
            dailyCapacity: dailyCapacity,
            completions: completions,
            historicalTargets: historicalTargets,
            policy: featurePolicy
        )
    }
}
