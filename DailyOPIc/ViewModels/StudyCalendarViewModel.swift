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

    /// 이 플랜에서 아직 잠겨 있는 자동화 기능(화면 노출 순서 그대로).
    /// 학습 알림은 설정 화면의 자기 카드에서 잠기므로 이 목록에 넣지 않는다.
    var lockedFeatures: [CalendarLockedFeature] {
        CalendarLockedFeature.automationCases.filter { $0.isLocked(under: featurePolicy) }
    }

    /// 학습 알림을 쓸 수 있는 플랜인가. 화면과 서비스는 플랜을 직접 보지 않고 이 값만 본다.
    var canUseStudyReminder: Bool { featurePolicy.canUseStudyReminder }

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
            // 다른 기기에서 계획을 바꿨을 수 있다. 캘린더 화면을 그리기 전에 한 번 맞춘다.
            Task { await reconcileStudyReminders() }
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
            // 알림 재조정은 저장 성공과 별개다. 여기서 실패해도 저장은 성공으로 남는다.
            Task { await reconcileStudyReminders() }
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

    // MARK: 학습 알림

    var studyReminders: StudyReminderService { environment.studyReminders }

    /// 최근 분석 결과의 예상 등급. 오래된 기록은 현재 실력으로 보지 않는다.
    /// 화면(@Query)과 알림 예약이 같은 규칙을 쓰도록 여기 한 곳에만 둔다.
    static func recentLevel(from record: PracticeHistoryRecord?, now: Date = .now) -> OPIcLevel? {
        guard let record else { return nil }
        let age = Calendar.current.dateComponents([.day], from: record.createdAt, to: now).day ?? 0
        guard age <= StudyPlanEstimatorConfig.recentLevelMaxAgeDays else { return nil }
        return record.predictedLevel
    }

    /// 지금 일정 기준으로 예약돼 있어야 할 알림. 캘린더 화면이 열려 있지 않아도 계산할 수 있도록
    /// @Query 대신 저장소에서 직접 읽는다(같은 기록이다).
    ///
    /// `nil`은 "아직 모른다"(계획 미로딩·저장소 미준비)이고 `[]`는 "예약할 것이 없다"이다.
    /// 둘을 같은 값으로 다루면, 앱이 켜지는 순간(계획을 읽기 전)의 재조정이 멀쩡한
    /// 앞으로의 예약을 전부 지워 버린다.
    func plannedReminders(now: Date = .now) -> [StudyReminderRequest]? {
        guard let settings, persistence.isReady else { return nil }
        let completions = StudyCalendarEngine.completionCounts(
            completedAt: (try? persistence.studySetCompletionDates()) ?? [],
            calendar: settings.calendar
        )
        let historicalTargets = ((try? persistence.studyDayPlans()) ?? [])
            .reduce(into: [String: Int]()) { $0[$1.localDate] = $1.targetSets }
        guard let snapshot = snapshot(
            completions: completions,
            recentLevel: Self.recentLevel(from: try? persistence.latestPracticeRecord(), now: now),
            historicalTargets: historicalTargets
        ) else { return [] }
        return StudyReminderPlanner.reminders(
            plan: snapshot.plan,
            settings: settings,
            completions: completions,
            now: now
        )
    }

    /// 대기 중인 알림을 현재 일정·현재 플랜과 같게 맞춘다. 여러 번 호출해도 결과가 같다.
    /// 계획을 아직 모르면(`nil`) 서비스가 예약을 건드리지 않는다.
    ///
    /// 학습 알림 자격 강제는 여기 **한 곳**에서만 한다. 앱 포그라운드 복귀·계획 로드·
    /// 설정 저장·학습 완료·플래너 진입이 전부 이 함수를 지나므로, 강등된 사용자의
    /// 예약은 다음 재조정에서 반드시 걷힌다.
    func reconcileStudyReminders(now: Date = .now) async {
        await studyReminders.reconcile(
            plannedReminders(now: now),
            isEligible: canUseStudyReminder
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
