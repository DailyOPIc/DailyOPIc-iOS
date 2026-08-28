import Foundation
import SwiftData

/// 한 항목의 학습 단계.
enum VocabularyStatus: String, Codable, CaseIterable, Sendable {
    /// 아직 학습한 적 없음. 저장만 해 둔 항목도 여기다.
    case new
    /// 학습했지만 지금 연속 성공 기록이 없음(오답 직후 포함).
    case learning
    /// 연속 성공이 1회 이상이지만 아직 익힘에 못 미침.
    case reviewing
    /// 연속 5회 성공. 30일마다 유지 복습으로 돌아온다.
    case mastered

    var label: String {
        switch self {
        case .new: "새 단어"
        case .learning: "학습 중"
        case .reviewing: "복습 중"
        case .mastered: "익힘"
        }
    }
}

/// 오늘 배정된 새 단어 묶음. 하루에 한 번만 정해지고, 같은 로컬 날짜 안에서는
/// 앱을 껐다 켜도 바뀌지 않는다.
///
/// 서버에 저장하지 않는다 — 배정은 기기에서 결정되고 네트워크가 없어도 돌아야 한다.
struct VocabularyDailySet: Codable, Equatable, Sendable {
    /// 기본 하루 목표. 화면 카피("0 / 10")도 이 값을 쓴다.
    static let dailyTarget = 10

    /// "yyyy-MM-dd"(학습 계획 타임존 기준).
    let localDate: String
    let entryIDs: [String]

    /// 오늘 쓸 배정인가. 후보가 바닥나 목록이 비어 있어도 그날의 답은 "이미 정했다"이다 —
    /// 비었다고 매번 다시 계산하면 화면을 열 때마다 배정이 흔들린다.
    func covers(_ today: String) -> Bool { localDate == today }
}

/// 오늘의 단어를 고르는 규칙. 순수 함수라 화면 없이 검증할 수 있다.
///
/// 여기 없는 것: 망각곡선 · 간격 반복 스케줄링 (P14.1).
enum VocabularyDailySetPlanner {
    /// 날짜 간격을 세기 위한 원점. 이 날짜 자체에는 의미가 없다(`OPIcTipCatalog`와 같은 방식).
    private static let epochLocalDate = "2000-01-01"

    /// 오늘 배정할 항목.
    ///
    /// - Parameters:
    ///   - localDate: 오늘의 "yyyy-MM-dd".
    ///   - catalog: 후보 전체(보통 `VocabularyCatalog.all`).
    ///   - excluding: 한 번이라도 학습한 항목 id. 오늘의 **새** 단어에서 빼낸다 —
    ///     이미 배운 단어는 복습 시스템의 몫이라 새 단어인 척 다시 나오지 않는다.
    ///   - targetLevel: 목표 등급. 맞는 항목으로 먼저 채우고, 모자라면 나머지로 메운다.
    static func assign(
        localDate: String,
        catalog: [VocabularyEntry],
        excluding excluded: Set<String> = [],
        targetLevel: OPIcLevel? = nil,
        count: Int = VocabularyDailySet.dailyTarget
    ) -> VocabularyDailySet {
        let candidates = catalog.filter { !excluded.contains($0.id) }
        guard !candidates.isEmpty, count > 0 else {
            return VocabularyDailySet(localDate: localDate, entryIDs: [])
        }
        // 주제별로 번갈아 세운 뒤 목표 등급에 맞는 것과 아닌 것으로 나눈다.
        // 순서를 지키는 변환들이라 같은 입력이면 언제나 같은 결과다.
        let interleaved = interleavedByTopic(candidates)
        let preferred = interleaved.filter { $0.matches(targetLevel: targetLevel) }
        let rest = interleaved.filter { !$0.matches(targetLevel: targetLevel) }

        // 목표 등급 쪽을 먼저 채우고 모자란 만큼만 나머지에서 가져온다. 목표 등급 항목이
        // 적으면 그 안에서 며칠 만에 한 바퀴를 돈다 — 반복 주기 조절은 P14.1(간격 반복)의 몫이다.
        // 후보가 목표보다 적으면 있는 만큼만 준다. 이미 배운 단어를 새 단어로 재활용하지 않는다.
        let head = window(preferred, localDate: localDate, count: count)
        let tail = window(rest, localDate: localDate, count: count - head.count)
        return VocabularyDailySet(localDate: localDate, entryIDs: (head + tail).map(\.id))
    }

    /// 날짜로 정해지는 시작점에서 `count`개를 끊어 온다. 끝을 넘으면 앞으로 돌아오고,
    /// 가져오는 개수가 목록 크기를 넘지 않으므로 같은 항목이 두 번 담기지 않는다.
    private static func window(
        _ entries: [VocabularyEntry],
        localDate: String,
        count: Int
    ) -> [VocabularyEntry] {
        guard !entries.isEmpty, count > 0 else { return [] }
        let start = abs(dayIndex(of: localDate) * count) % entries.count
        return (0..<min(count, entries.count)).map { entries[(start + $0) % entries.count] }
    }

    /// 대표 주제 기준 라운드로빈. 시드가 주제별로 뭉쳐 있어도 하루치 10개가
    /// 한 주제로만 채워지지 않게 한다.
    static func interleavedByTopic(_ entries: [VocabularyEntry]) -> [VocabularyEntry] {
        var order: [VocabularyTopic?] = []
        var buckets: [VocabularyTopic?: [VocabularyEntry]] = [:]
        for entry in entries {
            let key = entry.primaryTopic
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(entry)
        }
        var result: [VocabularyEntry] = []
        result.reserveCapacity(entries.count)
        var round = 0
        while result.count < entries.count {
            for key in order where round < (buckets[key]?.count ?? 0) {
                result.append(buckets[key]![round])
            }
            round += 1
        }
        return result
    }

    /// 원점부터 며칠째인가. 로컬 날짜 문자열만으로 결정되므로 타임존 변환을 다시 하지 않는다.
    static func dayIndex(of localDate: String) -> Int {
        let calendar = LocalCalendarDate.calendar(timeZone: .gmt)
        guard let epoch = LocalCalendarDate.date(from: epochLocalDate, timeZone: .gmt),
              let day = LocalCalendarDate.date(from: localDate, timeZone: .gmt)
        else { return 0 }
        return calendar.dateComponents([.day], from: epoch, to: day).day ?? 0
    }
}

/// 복습 일정 규칙. 앱에서 "다음에 언제 볼지"를 정하는 곳은 여기 하나다.
///
/// 연속 성공 1·2·3·4회 → 1 · 3 · 7 · 14일 뒤.
/// 5회째에 익힘이 되고, 그 뒤로는 30일마다 유지 복습으로 돌아온다.
/// "몰라요"는 연속 기록을 0으로 되돌리고 내일 다시 보게 한다(익힘이었어도 마찬가지다).
///
/// 날짜 계산은 달력 하루 단위다. 86400초를 더하지 않는다 — 서머타임이 있는 지역에서
/// 하루가 어긋난다.
enum VocabularyReviewPolicy {
    /// 연속 성공 n회 뒤 며칠을 쉬는가(1-based). 마지막 값이 익힘 이후의 유지 복습 간격이다.
    static let intervalDaysBySuccess = [1, 3, 7, 14, 30]

    /// 익힘이 되는 연속 성공 횟수.
    static let masteryThreshold = 5

    struct Outcome: Equatable {
        let status: VocabularyStatus
        /// 갱신된 연속 성공 횟수. 오답이면 0이다.
        let consecutiveSuccessCount: Int
        let nextReviewLocalDate: String
    }

    /// - Parameters:
    ///   - consecutiveSuccessCount: 이번 답 **이전**의 연속 성공 횟수.
    ///   - today: 학습 계획 타임존 기준 오늘("yyyy-MM-dd").
    static func apply(
        knewIt: Bool,
        consecutiveSuccessCount: Int,
        today: String,
        timeZone: TimeZone
    ) -> Outcome {
        guard knewIt else {
            // 익힘이었더라도 학습 중으로 내려온다. 잊은 단어는 잊은 단어다.
            return Outcome(
                status: .learning,
                consecutiveSuccessCount: 0,
                nextReviewLocalDate: localDate(today, addingDays: 1, timeZone: timeZone)
            )
        }
        let streak = consecutiveSuccessCount + 1
        // 5회를 넘어서면 계속 마지막 간격(30일)을 쓴다.
        let days = intervalDaysBySuccess[min(streak, intervalDaysBySuccess.count) - 1]
        return Outcome(
            status: streak >= masteryThreshold ? .mastered : .reviewing,
            consecutiveSuccessCount: streak,
            nextReviewLocalDate: localDate(today, addingDays: days, timeZone: timeZone)
        )
    }

    /// 로컬 날짜에 달력 하루씩 더한다.
    static func localDate(_ today: String, addingDays days: Int, timeZone: TimeZone) -> String {
        let calendar = LocalCalendarDate.calendar(timeZone: timeZone)
        guard let base = LocalCalendarDate.date(from: today, timeZone: timeZone),
              let moved = calendar.date(byAdding: .day, value: days, to: base)
        else { return today }
        return LocalCalendarDate.text(from: moved, timeZone: timeZone)
    }
}

/// 한 번의 학습 세션이 남은 항목을 어떤 순서로 내보내는가.
///
/// 화면이 배열을 직접 주무르지 않게 규칙을 여기 모은다. 틀린 항목은 세션 안에서
/// **한 번만** 다시 나온다 — 두 번째 오답은 그대로 넘어가고, 다음에 볼 날은
/// 저장된 일정(`VocabularyReviewPolicy`)이 정한다.
///
/// 이 큐는 앱을 끄면 사라진다. 그래도 되는 이유: 답한 결과는 이미 기기에 저장돼 있고,
/// 다시 열면 저장된 상태가 남은 항목을 다시 만들어 준다.
struct VocabularyStudySession {
    private(set) var pending: [VocabularyEntry]
    /// 이번 세션에서 한 번이라도 답한 항목. 다시 나온 항목을 두 번 세지 않는다.
    private(set) var attemptedIDs: Set<String> = []
    /// 한 번이라도 틀린 항목. 마무리 화면의 "다시 볼 표현"이다.
    private(set) var forgottenIDs: Set<String> = []
    /// 이미 한 번 다시 넣은 항목. 무한 반복을 막는 유일한 장치다.
    private var requeuedIDs: Set<String> = []

    init(entries: [VocabularyEntry]) {
        pending = entries
    }

    var current: VocabularyEntry? { pending.first }
    var isFinished: Bool { pending.isEmpty }
    /// 서로 다른 항목 기준 진행도. 다시 나온 항목은 다시 세지 않는다.
    var attemptedCount: Int { attemptedIDs.count }
    var knownCount: Int { attemptedIDs.subtracting(forgottenIDs).count }
    var forgottenCount: Int { forgottenIDs.count }

    /// 지금 항목에 답하고 다음 항목으로 넘어간다.
    mutating func answer(knewIt: Bool) {
        guard !pending.isEmpty else { return }
        let entry = pending.removeFirst()
        attemptedIDs.insert(entry.id)
        guard !knewIt else { return }
        forgottenIDs.insert(entry.id)
        // 뒤로 보낸다. 바로 다음에 같은 카드가 나오지 않게 하기 위해서다
        // (남은 것이 없으면 어쩔 수 없이 바로 다음이 된다).
        if requeuedIDs.insert(entry.id).inserted {
            pending.append(entry)
        }
    }
}

/// 홈 화면이 세는 값들. 화면 안에 두면 검증할 방법이 없어서 순수 함수로 꺼내 둔다.
/// 모두 저장된 기록만 보고 계산한다 — 별도 카운터를 만들지 않는다.
enum VocabularyDailyProgress {
    /// 오늘 배정분 중 한 번이라도 답한 항목 수("3 / 10"의 분자).
    /// 알아요·몰라요를 가리지 않고, 같은 항목을 두 번 답해도 한 번만 센다.
    static func attemptedCount(
        assigned: [String],
        states: [String: VocabularyStateRecord],
        today: String
    ) -> Int {
        assigned.count { states[$0]?.wasStudied(on: today) == true }
    }

    /// 오늘 아직 답하지 않은 배정분. "이어서 학습"은 여기서부터 이어진다.
    static func remainingIDs(
        assigned: [String],
        states: [String: VocabularyStateRecord],
        today: String
    ) -> [String] {
        assigned.filter { states[$0]?.wasStudied(on: today) != true }
    }

    /// 오늘 복습할 항목. 예정일이 오늘이거나 지난 것만 들어온다 —
    /// 미래 일정과 아직 배우지 않은 단어는 빠지고, 익힘의 유지 복습은 들어온다.
    static func dueIDs(states: [VocabularyStateRecord], today: String) -> [String] {
        states.filter { $0.isDueForReview(on: today) }.map(\.entryID)
    }

    /// 오늘의 **새** 단어 후보에서 빼야 할 항목. 저장만 해 둔 항목은 빠지지 않는다.
    static func studiedIDs(states: [VocabularyStateRecord]) -> Set<String> {
        Set(states.filter(\.hasBeenStudied).map(\.entryID))
    }
}
