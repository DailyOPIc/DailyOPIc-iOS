import Foundation
import SwiftData
import Testing
@testable import DailyOPIc

/// P14.5.1 저장소가 P14.5.2 스키마로 **그대로 열리는가**(디스크 실측).
///
/// 이 파일의 테스트는 메모리 저장소를 쓰지 않는다. 임시 폴더에 진짜 `.store` 파일을
/// 만들고, 닫고, 다시 여는 것까지 한다 — 자동 lightweight migration은 디스크에
/// 실제 파일이 있어야만 일어나기 때문이다.
///
/// 저장소를 지우거나 초기화하는 fallback은 없다. 열리지 않으면 테스트가 실패해야 하지,
/// 조용히 데이터를 버려서 통과하면 안 된다.
/// P14.5.1 저장소를 만들기 위한 **테스트 전용** 네임스페이스.
///
/// SwiftData의 엔티티 이름은 타입의 짧은 이름이라, 여기 담긴 `VocabularyStateRecord`는
/// 프로덕션 모델과 **같은 엔티티**로 열린다 — 다른 이름을 쓰면 같은 테이블이 아니게 되고,
/// 그러면 마이그레이션이 아니라 빈 저장소를 여는 셈이 된다.
/// 네임스페이스 안에 있으니 다른 테스트 파일의 `VocabularyStateRecord`는 그대로 프로덕션 것이다.
enum LegacyP1451 {
    /// P14.5.1의 `VocabularyStateRecord` 그대로 — `reviewCount`만 없다.
    @Model
    final class VocabularyStateRecord {
        @Attribute(.unique) var entryID: String
        var statusRaw: String
        var isSaved: Bool
        var consecutiveSuccessCount: Int
        var failureCount: Int
        var lastStudiedLocalDate: String?
        var nextReviewLocalDate: String?
        var updatedAt: Date

        init(
            entryID: String,
            statusRaw: String,
            isSaved: Bool,
            consecutiveSuccessCount: Int,
            failureCount: Int,
            lastStudiedLocalDate: String?,
            nextReviewLocalDate: String?,
            updatedAt: Date
        ) {
            self.entryID = entryID
            self.statusRaw = statusRaw
            self.isSaved = isSaved
            self.consecutiveSuccessCount = consecutiveSuccessCount
            self.failureCount = failureCount
            self.lastStudiedLocalDate = lastStudiedLocalDate
            self.nextReviewLocalDate = nextReviewLocalDate
            self.updatedAt = updatedAt
        }
    }
}

@MainActor
struct SchemaMigrationTests {
    // MARK: 도우미

    /// 이 테스트만 쓰는 빈 폴더. 앱 저장소와 절대 겹치지 않는다.
    private func makeStoreURL() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SchemaMigrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("DailyOPIc.store")
    }

    private func container(_ schema: Schema, at url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
    }

    // MARK: 1. 옛 저장소 → 현재 스키마

    /// P14.5.1 모양(= `reviewCount` 없음 · `StudyActivityDailyRecord` 없음)으로 디스크에
    /// 저장소를 만들고, 그 **같은 파일**을 현재 `Schema.dailyOPIc`로 다시 연다.
    @Test func p1451StoreOpensWithTodaysSchemaAndKeepsItsData() throws {
        let url = try makeStoreURL()

        // (1) 옛 스키마로 쓰기.
        do {
            let legacy = try container(Schema([LegacyP1451.VocabularyStateRecord.self]), at: url)
            let context = ModelContext(legacy)
            context.insert(
                LegacyP1451.VocabularyStateRecord(
                    entryID: "cafe-crowded",
                    statusRaw: "reviewing",
                    isSaved: true,
                    consecutiveSuccessCount: 2,
                    failureCount: 1,
                    lastStudiedLocalDate: "2026-08-20",
                    nextReviewLocalDate: "2026-08-23",
                    updatedAt: Date(timeIntervalSince1970: 1_780_000_000)
                )
            )
            try context.save()
        }
        #expect(FileManager.default.fileExists(atPath: url.path))

        // (2) 현재 스키마로 같은 파일 열기. 실패하면 여기서 throw 된다 — 지우고 다시 만들지 않는다.
        let upgraded = try container(Schema.dailyOPIc, at: url)
        let context = ModelContext(upgraded)
        let states = try context.fetch(FetchDescriptor<VocabularyStateRecord>())

        // 기존 데이터가 그대로 남는다.
        #expect(states.count == 1)
        let state = try #require(states.first)
        #expect(state.entryID == "cafe-crowded")
        #expect(state.status == .reviewing)
        #expect(state.isSaved)
        #expect(state.consecutiveSuccessCount == 2)
        #expect(state.failureCount == 1)
        #expect(state.lastStudiedLocalDate == "2026-08-20")
        #expect(state.nextReviewLocalDate == "2026-08-23")
        // 새 필드는 안전한 0에서 시작한다 — 예전 사용자에게 없던 복습 횟수를 지어내지 않는다.
        #expect(state.reviewCount == 0)

        // 새 모델도 바로 쓸 수 있다.
        context.insert(
            StudyActivityDailyRecord(
                localDate: "2026-08-28",
                vocabularyStudiedCount: 20,
                vocabularyGoalCount: 20,
                updatedAt: Date(timeIntervalSince1970: 1_780_100_000)
            )
        )
        try context.save()

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// 옮겨 온 저장소를 **한 번 더** 닫았다 열어도 값이 그대로다. 마이그레이션이
    /// 메모리에서만 성공하고 디스크에는 안 남는 경우를 잡는다.
    @Test func migratedStoreSurvivesAnotherReopen() throws {
        let url = try makeStoreURL()
        do {
            let legacy = try container(Schema([LegacyP1451.VocabularyStateRecord.self]), at: url)
            let context = ModelContext(legacy)
            context.insert(
                LegacyP1451.VocabularyStateRecord(
                    entryID: "park-jog",
                    statusRaw: "learning",
                    isSaved: false,
                    consecutiveSuccessCount: 0,
                    failureCount: 3,
                    lastStudiedLocalDate: "2026-08-19",
                    nextReviewLocalDate: "2026-08-20",
                    updatedAt: .now
                )
            )
            try context.save()
        }
        do {
            let upgraded = try container(Schema.dailyOPIc, at: url)
            let context = ModelContext(upgraded)
            context.insert(
                StudyActivityDailyRecord(
                    localDate: "2026-08-27", vocabularyStudiedCount: 7, vocabularyGoalCount: 20
                )
            )
            try context.save()
        }

        let reopened = try container(Schema.dailyOPIc, at: url)
        let context = ModelContext(reopened)
        let state = try #require(try context.fetch(FetchDescriptor<VocabularyStateRecord>()).first)
        #expect(state.entryID == "park-jog")
        #expect(state.failureCount == 3)
        #expect(state.reviewCount == 0)
        let activity = try #require(
            try context.fetch(FetchDescriptor<StudyActivityDailyRecord>()).first
        )
        #expect(activity.localDate == "2026-08-27")
        #expect(activity.vocabularyStudiedCount == 7)
        #expect(activity.vocabularyGoalCount == 20)

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// 옮겨 온 기록 위에서 P14.5.2 기능이 실제로 돈다 — 복습 횟수가 0에서 1로 오르고,
    /// 날짜별 학습량이 쌓인다.
    @Test func migratedRecordKeepsCountingFromZero() throws {
        let url = try makeStoreURL()
        do {
            let legacy = try container(Schema([LegacyP1451.VocabularyStateRecord.self]), at: url)
            let context = ModelContext(legacy)
            context.insert(
                LegacyP1451.VocabularyStateRecord(
                    entryID: "cafe-crowded",
                    statusRaw: "reviewing",
                    isSaved: false,
                    consecutiveSuccessCount: 1,
                    failureCount: 0,
                    lastStudiedLocalDate: "2026-08-27",
                    nextReviewLocalDate: "2026-08-28",
                    updatedAt: .now
                )
            )
            try context.save()
        }

        let seoul = try #require(TimeZone(identifier: "Asia/Seoul"))
        let service = PersistenceService()
        service.configure(context: ModelContext(try container(Schema.dailyOPIc, at: url)))
        let now = try #require(LocalCalendarDate.date(from: "2026-08-28", timeZone: seoul))
            .addingTimeInterval(9 * 3600)
        try service.recordVocabularyAnswer(
            entryID: "cafe-crowded", knewIt: true, timeZone: seoul, now: now
        )

        let state = try #require(try service.vocabularyStates().first)
        // 날이 바뀌어 다시 만났으므로 0 → 1. 예전 학습 이력을 소급해 채우지 않는다.
        #expect(state.reviewCount == 1)
        #expect(state.lastStudiedLocalDate == "2026-08-28")
        let activity = try #require(try service.studyActivityRecords().first)
        #expect(activity.localDate == "2026-08-28")
        #expect(activity.vocabularyStudiedCount == 1)

        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: 2. 자동 마이그레이션이 기대는 조건

    /// P14.5.2가 스키마에 한 일은 **추가뿐**이다. 새 저장 프로퍼티에는 기본값이 있고,
    /// 기존 모델 목록에서 빠진 것이 없다 — 둘 중 하나라도 깨지면 자동 마이그레이션이
    /// 아니라 저장소 재생성이 된다.
    @Test func schemaOnlyGrewAndTheNewFieldHasADefault() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
        let records = try String(
            contentsOf: root.appendingPathComponent("Models/LocalRecords.swift"), encoding: .utf8
        )
        #expect(records.contains("var reviewCount: Int = 0"))

        let app = try String(
            contentsOf: root.appendingPathComponent("DailyOPIcApp.swift"), encoding: .utf8
        )
        for model in [
            "PracticeHistoryRecord", "MockHistoryRecord", "MockDraftRecord",
            "StudySetCompletionRecord", "StudyDayPlanRecord", "PlannerEventRecord",
            "PlannerLearnedQuestionRecord", "VocabularyStateRecord",
            "VocabularyGeneratedSetRecord", "VocabularyCoachResultRecord",
            "StudyActivityDailyRecord"
        ] {
            #expect(app.contains("\(model).self"), "\(model)이(가) 스키마 목록에서 빠졌다")
        }
        // 버전 마이그레이션 아키텍처를 새로 넣지 않았다(추가만 하는 변경이라 필요 없다).
        #expect(!app.contains("SchemaMigrationPlan"))
        #expect(!app.contains("VersionedSchema"))
    }
}
