import Foundation

/// 한 항목의 학습 단계.
enum VocabularyStatus: String, Codable, CaseIterable, Sendable {
    /// 아직 한 번도 보지 않음.
    case new
    /// 봤지만 아직 못 맞힌 적이 있음.
    case learning
    /// 한 번 맞혔고 다시 볼 예정.
    case reviewing
    /// 익힘.
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

    func isValid(on today: String) -> Bool { localDate == today && !entryIDs.isEmpty }
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
    ///   - excluding: 이미 익힌 항목 id. 오늘의 **새** 단어에서 빼낸다.
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

/// 카드에서 "알아요 / 몰라요"를 눌렀을 때 상태가 어떻게 움직이는지.
///
/// **잠정 규칙이다.** P14는 기록만 남기고, 실제 간격 반복(SM-2류) 스케줄링은 P14.1에서
/// 이 한 곳을 교체해 넣는다. 지금은 "못 맞히면 오늘 다시, 맞히면 내일 다시, 두 번 맞히면 익힘"뿐이다.
enum VocabularyReviewPolicy {
    /// 익힘으로 넘어가는 데 필요한 연속 성공 횟수.
    static let masteryThreshold = 2

    struct Outcome: Equatable {
        let status: VocabularyStatus
        let nextReviewAt: Date?
    }

    static func apply(
        knewIt: Bool,
        successCount: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> Outcome {
        guard knewIt else {
            // 오늘 안에 다시 만난다. 다음 날로 밀지 않는다.
            return Outcome(status: .learning, nextReviewAt: now)
        }
        if successCount >= masteryThreshold {
            return Outcome(status: .mastered, nextReviewAt: nil)
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        return Outcome(status: .reviewing, nextReviewAt: tomorrow)
    }
}
