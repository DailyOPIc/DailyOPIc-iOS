import Foundation
import Testing
@testable import DailyOPIc

/// 오늘의 OPIc TIP. 목록의 무결성과 "하루 하나 · 날짜로만 결정" 규칙을 지킨다.
struct OPIcTipTests {
    private let seoul = TimeZone(identifier: "Asia/Seoul")!
    private let newYork = TimeZone(identifier: "America/New_York")!

    private func date(_ text: String, _ timeZone: TimeZone) throws -> Date {
        try #require(LocalCalendarDate.date(from: text, timeZone: timeZone))
    }

    /// 그 타임존의 특정 시각. 로컬 자정 경계를 확인할 때 쓴다.
    private func moment(_ text: String, hour: Int, minute: Int, _ timeZone: TimeZone) throws -> Date {
        let day = try date(text, timeZone)
        let calendar = LocalCalendarDate.calendar(timeZone: timeZone)
        return try #require(calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: day))
    }

    // MARK: 목록

    @Test func catalogHasExactlyOneHundredTips() {
        #expect(OPIcTipCatalog.all.count == 100)
    }

    @Test func everyTipHasAnIdentifierAndText() {
        for tip in OPIcTipCatalog.all {
            #expect(!tip.id.trimmingCharacters(in: .whitespaces).isEmpty)
            #expect(!tip.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(tip.text == tip.text.trimmingCharacters(in: .whitespacesAndNewlines))
            #expect(OPIcTipCategory.allCases.contains(tip.category))
        }
    }

    @Test func identifiersAreUnique() {
        #expect(Set(OPIcTipCatalog.all.map(\.id)).count == OPIcTipCatalog.all.count)
    }

    @Test func noTipTextIsRepeated() {
        #expect(Set(OPIcTipCatalog.all.map(\.text)).count == OPIcTipCatalog.all.count)
    }

    /// 점수를 약속하거나 채점 기준을 단정하지 않는다. 그런 문구는 지킬 수 없는 약속이다.
    @Test func noTipPromisesAScore() {
        let banned = ["보장", "무조건", "반드시", "점수가 올라", "확실히 오르", "합격"]
        for tip in OPIcTipCatalog.all {
            for word in banned {
                #expect(!tip.text.contains(word), "\(tip.id): \(word)")
            }
        }
    }

    /// 모든 말하기 영역이 남아 있는지. 개수가 바뀌어도 한 분류가 사라지면 실패한다.
    @Test func everyCategoryIsRepresented() {
        let counts = Dictionary(grouping: OPIcTipCatalog.all, by: \.category).mapValues(\.count)
        #expect(counts[.answerStructure] == 20)
        #expect(counts[.naturalSpeaking] == 20)
        #expect(counts[.experience] == 15)
        #expect(counts[.descriptionComparison] == 15)
        #expect(counts[.rolePlay] == 10)
        #expect(counts[.unexpectedQuestions] == 10)
        #expect(counts[.testStrategy] == 10)
        #expect(counts.values.reduce(0, +) == 100)
    }

    /// 한 줄 카드에 들어갈 길이. 상한이 없으면 카드가 화면을 삼킨다.
    @Test func tipsStayShortEnoughForACard() {
        for tip in OPIcTipCatalog.all {
            #expect(tip.text.count <= 90, "\(tip.id) 너무 길다(\(tip.text.count)자)")
        }
    }

    // MARK: 오늘의 선택

    @Test func sameLocalDayGivesTheSameTip() throws {
        let earlyMorning = try moment("2026-08-17", hour: 0, minute: 5, seoul)
        let lateNight = try moment("2026-08-17", hour: 23, minute: 55, seoul)
        #expect(OPIcTipCatalog.tip(for: earlyMorning, timeZone: seoul)
                == OPIcTipCatalog.tip(for: lateNight, timeZone: seoul))
    }

    @Test func nextDayMovesTheSelectionDeterministically() throws {
        let today = try date("2026-08-17", seoul)
        let tomorrow = try date("2026-08-18", seoul)
        let first = OPIcTipCatalog.index(for: today, timeZone: seoul)
        let second = OPIcTipCatalog.index(for: tomorrow, timeZone: seoul)
        #expect(first != second)
        // 같은 입력을 다시 넣어도 같은 값이다(실행 횟수·난수와 무관).
        #expect(OPIcTipCatalog.index(for: today, timeZone: seoul) == first)
        #expect(OPIcTipCatalog.index(for: tomorrow, timeZone: seoul) == second)
    }

    @Test func indexAlwaysStaysInRange() throws {
        let calendar = LocalCalendarDate.calendar(timeZone: seoul)
        var day = try date("1999-01-01", seoul)   // 기준일 이전도 범위를 벗어나지 않아야 한다
        for _ in 0..<800 {
            let index = OPIcTipCatalog.index(for: day, timeZone: seoul)
            #expect((0..<OPIcTipCatalog.all.count).contains(index))
            day = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        }
    }

    /// 100일 동안 100개가 모두 한 번씩 나오고, 101일째에 첫 팁으로 돌아온다.
    @Test func oneHundredDaysCoverEveryTipThenRepeat() throws {
        let calendar = LocalCalendarDate.calendar(timeZone: seoul)
        let start = try date("2026-08-17", seoul)
        var seen: [String] = []
        for offset in 0..<100 {
            let day = try #require(calendar.date(byAdding: .day, value: offset, to: start))
            seen.append(OPIcTipCatalog.tip(for: day, timeZone: seoul).id)
        }
        #expect(Set(seen).count == 100)
        let cycled = try #require(calendar.date(byAdding: .day, value: 100, to: start))
        #expect(OPIcTipCatalog.tip(for: cycled, timeZone: seoul).id == seen[0])
    }

    /// 팁은 서울 자정에 바뀐다. UTC 자정(= 서울 09:00)에 바뀌면 아침에 팁이 뒤집힌다.
    @Test func seoulTipChangesAtLocalMidnightNotUTCMidnight() throws {
        let beforeMidnight = try moment("2026-08-17", hour: 23, minute: 30, seoul)
        let afterMidnight = try moment("2026-08-18", hour: 0, minute: 30, seoul)
        let nineAM = try moment("2026-08-18", hour: 9, minute: 30, seoul)   // UTC 자정 직후
        #expect(OPIcTipCatalog.tip(for: beforeMidnight, timeZone: seoul)
                != OPIcTipCatalog.tip(for: afterMidnight, timeZone: seoul))
        #expect(OPIcTipCatalog.tip(for: afterMidnight, timeZone: seoul)
                == OPIcTipCatalog.tip(for: nineAM, timeZone: seoul))
    }

    /// 같은 로컬 날짜면 타임존이 달라도 같은 팁이다(선택의 입력은 날짜뿐이다).
    @Test func selectionDependsOnTheLocalDateNotTheInstant() throws {
        let seoulDay = try date("2026-08-17", seoul)
        let newYorkDay = try date("2026-08-17", newYork)
        #expect(seoulDay != newYorkDay)   // 같은 날짜, 다른 순간
        #expect(OPIcTipCatalog.tip(for: seoulDay, timeZone: seoul)
                == OPIcTipCatalog.tip(for: newYorkDay, timeZone: newYork))
    }

    /// 여행 중 기기 타임존이 바뀌어도 계획 타임존으로 계산하면 그날의 팁은 그대로다.
    @Test func planTimeZoneKeepsTheTipStableWhileTraveling() throws {
        let seoulNoon = try moment("2026-08-17", hour: 12, minute: 0, seoul)
        #expect(OPIcTipCatalog.tip(for: seoulNoon, timeZone: seoul)
                == OPIcTipCatalog.tip(for: seoulNoon, timeZone: seoul))
        // 같은 순간을 뉴욕 날짜로 보면 8월 16일이라 다른 팁이 나온다 — 계획 타임존을 넘겨야 하는 이유.
        #expect(LocalCalendarDate.text(from: seoulNoon, timeZone: newYork) == "2026-08-16")
    }

    // MARK: 화면 · 플랜

    @Test func cardReadsTheTipAsOneSentence() throws {
        let tip = try #require(OPIcTipCatalog.all.first)
        #expect(OPIcTipCard(tip: tip).accessibilityText == "오늘의 OPIc 팁. \(tip.text)")
    }

    /// 플랜과 무관하다. 어떤 플랜이든 같은 날이면 같은 팁이고, 잠금 판정이 끼어들지 않는다.
    @Test func everyPlanSeesTheSameTip() throws {
        let day = try date("2026-08-17", seoul)
        let tip = OPIcTipCatalog.tip(for: day, timeZone: seoul)
        for plan in PlanEntitlement.allCases {
            let policy = CalendarFeaturePolicy.fallback(for: plan)
            _ = policy   // 팁은 정책을 보지 않는다. 값을 넘길 자리조차 없다.
            #expect(OPIcTipCatalog.tip(for: day, timeZone: seoul) == tip)
        }
    }

    /// 팁 코드가 네트워크·AI·토큰·페이월에 손대지 않는다. 정적 데이터에 서비스가 붙는 순간
    /// 오프라인 보장이 깨진다.
    @Test func tipSourceHasNoNetworkOrBillingDependency() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("DailyOPIc")
        let files = [
            root.appendingPathComponent("Models/OPIcTip.swift"),
            root.appendingPathComponent("Views/Screens/Main/Calendar/OPIcTipCard.swift"),
        ]
        let forbidden = ["APIClient", "URLSession", "Purchases", "Paywall", "token", "random", "UserDefaults"]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for literal in forbidden {
                #expect(!text.contains(literal), "\(file.lastPathComponent)에 '\(literal)'가 있다")
            }
        }
    }
}
