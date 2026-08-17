import Foundation

/// 학습 강도. 세트 수는 "권장 학습량"이지 보장된 소요 시간이 아니다.
enum StudyIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case light
    case steady
    case focused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "가볍게"
        case .steady: "꾸준히"
        case .focused: "집중"
        }
    }

    /// 하루에 하고 싶은 Daily 세트 수. 실제 목표는 플랜 토큰 한도로 한 번 더 깎인다
    /// (`StudyPlanEstimator.effectiveDailyTarget`).
    var desiredDailySets: Int {
        switch self {
        case .light: 1
        case .steady: 2
        case .focused: 3
        }
    }

    var summary: String {
        switch self {
        case .light: "하루 1세트 · 약 10~15분"
        case .steady: "하루 2세트 · 약 20~30분"
        case .focused: "하루 3세트 · 약 30~45분"
        }
    }
}

/// ISO 8601 요일(월=1 … 일=7). 서버와 같은 번호를 쓴다.
/// `Calendar`의 weekday(일=1)와 다르므로 변환은 반드시 `from(date:calendar:)`로 한다.
enum StudyWeekday: Int, Codable, CaseIterable, Identifiable, Sendable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .monday: "월"
        case .tuesday: "화"
        case .wednesday: "수"
        case .thursday: "목"
        case .friday: "금"
        case .saturday: "토"
        case .sunday: "일"
        }
    }

    /// VoiceOver는 "월"을 요일로 읽지 못한다.
    var accessibilityLabel: String { "\(shortLabel)요일" }

    /// 화면에 늘어놓는 순서(일~토). **표시 순서일 뿐** 저장·전송 값은 ISO 그대로다(월=1 … 일=7).
    static let displayOrder: [StudyWeekday] = [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday
    ]

    /// 일요일 시작 격자에서 이 요일이 놓일 열(일=0 … 토=6).
    /// 주간 스트립·월간 격자·요일 선택이 전부 이 값 하나로 자리를 잡는다.
    var displayColumn: Int { rawValue % 7 }

    static func from(date: Date, calendar: Calendar = .current) -> StudyWeekday {
        // Calendar.weekday: 일=1 … 토=7 → ISO: 월=1 … 일=7
        let iso = (calendar.component(.weekday, from: date) + 5) % 7 + 1
        return StudyWeekday(rawValue: iso) ?? .monday
    }

    static func < (lhs: StudyWeekday, rhs: StudyWeekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// 로컬 벽시계 시각. 알림 예약(G5)이 쓸 값이라 절대 시각(Date)으로 저장하지 않는다.
struct StudyTimeOfDay: Codable, Equatable, Sendable {
    var hour: Int
    var minute: Int

    static let evening = StudyTimeOfDay(hour: 21, minute: 0)

    var wireValue: String { String(format: "%02d:%02d", hour, minute) }

    init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    init?(wireValue: String) {
        let parts = wireValue.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            return nil
        }
        self.init(hour: parts[0], minute: parts[1])
    }

    /// 오늘 날짜에 이 시각을 붙인 Date. 피커 바인딩과 로케일 표기에 쓴다.
    func date(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 21, minute: parts.minute ?? 0)
    }

    var displayText: String {
        date().formatted(date: .omitted, time: .shortened)
    }
}

/// 로컬 달력 날짜("yyyy-MM-dd") 변환. DateFormatter를 쓰지 않는 이유는 로케일·달력
/// 설정(불교력 등)에 따라 문자열이 흔들리기 때문이다.
enum LocalCalendarDate {
    static func calendar(timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func date(from text: String, timeZone: TimeZone) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar(timeZone: timeZone)
            .date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func text(from date: Date, timeZone: TimeZone) -> String {
        let parts = calendar(timeZone: timeZone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// 학습 계획 설정. 목표 등급은 여기 없다 — `AppPreferences.targetLevel`과 서버
/// `userProfiles.targetLevel`이 이미 진실이고, 복제하면 두 값이 갈라진다.
/// 구독 플랜도 담지 않는다(엔타이틀먼트에서 실시간으로 온다).
/// 파생값(예상 완료일 등)도 저장하지 않고 매번 계산한다.
struct StudyPlanSettings: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var examDate: Date?
    var studyWeekdays: Set<StudyWeekday>
    var intensity: StudyIntensity
    var preferredStudyTime: StudyTimeOfDay
    var timezoneIdentifier: String
    var createdAt: Date?
    var updatedAt: Date?

    var timeZone: TimeZone { TimeZone(identifier: timezoneIdentifier) ?? .current }
    var calendar: Calendar { LocalCalendarDate.calendar(timeZone: timeZone) }
    var sortedWeekdays: [StudyWeekday] { studyWeekdays.sorted() }

    init(
        schemaVersion: Int = StudyPlanSettings.currentSchemaVersion,
        examDate: Date? = nil,
        studyWeekdays: Set<StudyWeekday>,
        intensity: StudyIntensity,
        preferredStudyTime: StudyTimeOfDay,
        timezoneIdentifier: String = TimeZone.current.identifier,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.examDate = examDate
        self.studyWeekdays = studyWeekdays
        self.intensity = intensity
        self.preferredStudyTime = preferredStudyTime
        self.timezoneIdentifier = timezoneIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 온보딩 기본값. 첫 화면부터 아무것도 선택되지 않은 상태를 보여주지 않는다.
    static var draft: StudyPlanSettings {
        StudyPlanSettings(
            studyWeekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
            intensity: .steady,
            preferredStudyTime: .evening
        )
    }

    func isStudyDay(_ date: Date) -> Bool {
        studyWeekdays.contains(StudyWeekday.from(date: date, calendar: calendar))
    }

    // 서버 계약: examDate는 "yyyy-MM-dd", preferredStudyTime은 "HH:mm",
    // studyWeekdays는 정렬된 ISO 요일 배열. 두 필드 모두 절대 시각이 아니라
    // 사용자의 로컬 값이므로 Date/ISO8601로 실어 보내면 타임존만큼 밀린다.
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, examDate, studyWeekdays, intensity, preferredStudyTime
        case timezoneIdentifier, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let timezoneIdentifier = try container.decode(String.self, forKey: .timezoneIdentifier)
        let timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
        let time = try container.decode(String.self, forKey: .preferredStudyTime)
        self.init(
            schemaVersion: try container.decodeIfPresent(Int.self, forKey: .schemaVersion)
                ?? Self.currentSchemaVersion,
            examDate: try container.decodeIfPresent(String.self, forKey: .examDate)
                .flatMap { LocalCalendarDate.date(from: $0, timeZone: timeZone) },
            studyWeekdays: Set(try container.decode([StudyWeekday].self, forKey: .studyWeekdays)),
            intensity: try container.decode(StudyIntensity.self, forKey: .intensity),
            preferredStudyTime: StudyTimeOfDay(wireValue: time) ?? .evening,
            timezoneIdentifier: timezoneIdentifier,
            createdAt: try container.decodeIfPresent(Date.self, forKey: .createdAt),
            updatedAt: try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encodeIfPresent(
            examDate.map { LocalCalendarDate.text(from: $0, timeZone: timeZone) },
            forKey: .examDate
        )
        try container.encode(sortedWeekdays, forKey: .studyWeekdays)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(preferredStudyTime.wireValue, forKey: .preferredStudyTime)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }
}

/// `GET/PUT /v1/users/me/study-plan`. 설정이 없는 기존 사용자는 오류가 아니라
/// `configured == false`다.
struct StudyPlanResponse: Codable, Sendable {
    let configured: Bool
    let studyPlan: StudyPlanSettings?
}

/// PUT 본문. 서버가 매기는 값(schemaVersion, createdAt, updatedAt)은 보내지 않는다.
struct StudyPlanRequest: Encodable, Sendable {
    let examDate: String?
    let studyWeekdays: [Int]
    let intensity: StudyIntensity
    let preferredStudyTime: String
    let timezoneIdentifier: String

    init(settings: StudyPlanSettings) {
        examDate = settings.examDate.map {
            LocalCalendarDate.text(from: $0, timeZone: settings.timeZone)
        }
        studyWeekdays = settings.sortedWeekdays.map(\.rawValue)
        intensity = settings.intensity
        preferredStudyTime = settings.preferredStudyTime.wireValue
        timezoneIdentifier = settings.timezoneIdentifier
    }
}
