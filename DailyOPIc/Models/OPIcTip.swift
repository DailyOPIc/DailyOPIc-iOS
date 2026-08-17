import Foundation

/// 오늘의 OPIc TIP 한 줄.
///
/// 앱에 담아 배포하는 **고정 문구**다. 서버·AI·원격 설정에서 오지 않으므로 오프라인에서도,
/// 로그인 전에도, capabilities를 못 받아도 똑같이 보인다.
struct OPIcTip: Identifiable, Equatable, Sendable {
    let id: String
    let category: OPIcTipCategory
    let text: String
}

/// 팁의 분류. 카드에는 노출하지 않고(문구 하나면 충분하다) 목록의 균형을 지키는 용도다.
enum OPIcTipCategory: String, CaseIterable, Sendable {
    case answerStructure
    case naturalSpeaking
    case experience
    case descriptionComparison
    case rolePlay
    case unexpectedQuestions
    case testStrategy

    /// 화면에 분류를 보여줄 일이 생기면 쓸 한국어 라벨.
    var label: String {
        switch self {
        case .answerStructure: "답변 구조"
        case .naturalSpeaking: "자연스러운 말하기"
        case .experience: "경험 질문"
        case .descriptionComparison: "묘사·비교"
        case .rolePlay: "롤플레이"
        case .unexpectedQuestions: "돌발 질문"
        case .testStrategy: "시험 운영·멘탈"
        }
    }
}

/// 100개의 팁과 "오늘의 한 개"를 고르는 규칙. 상태를 갖지 않는다 —
/// 이미 본 팁을 기억하려고 저장소를 새로 만들지 않는다(중복은 100일 뒤에 한 번 돈다).
enum OPIcTipCatalog {
    /// 하루가 지날 때마다 목록을 이만큼 건너뛴다. 7과 100은 서로소라 100일 동안 100개가
    /// 정확히 한 번씩 나오고, 배열이 분류별로 뭉쳐 있어도 며칠 연속 같은 분류가 나오지 않는다.
    private static let strideDays = 7
    /// 기준일. 이 날짜 자체는 아무 의미가 없고, 로컬 날짜 사이의 간격을 세기 위한 원점이다.
    private static let epochLocalDate = "2000-01-01"

    /// 오늘의 팁. `date`는 학습 계획 타임존의 하루(예: `snapshot.today.date`)를 넘긴다.
    static func tip(for date: Date, timeZone: TimeZone) -> OPIcTip {
        all[index(for: date, timeZone: timeZone)]
    }

    /// 로컬 달력 날짜에서만 나오는 결정적 인덱스. 같은 날이면 몇 번을 호출해도 같은 값이고,
    /// UTC 자정이 아니라 **그 타임존의 자정**에 바뀐다.
    static func index(for date: Date, timeZone: TimeZone) -> Int {
        let calendar = LocalCalendarDate.calendar(timeZone: timeZone)
        guard let epoch = LocalCalendarDate.date(from: epochLocalDate, timeZone: timeZone) else { return 0 }
        let days = calendar.dateComponents([.day], from: epoch, to: calendar.startOfDay(for: date)).day ?? 0
        let slot = (days * strideDays) % all.count
        // 기기 시계가 기준일보다 과거면 음수가 나온다. 그래도 범위 밖으로 나가지 않는다.
        return slot < 0 ? slot + all.count : slot
    }

    /// 정확히 100개. 문구는 전부 직접 쓴 것이고 외부 자료를 옮기지 않았다.
    /// 점수 보장·공식 채점 기준 주장·"무조건" 같은 단정은 쓰지 않는다.
    static let all: [OPIcTip] = answerStructure + naturalSpeaking + experience
        + descriptionComparison + rolePlay + unexpectedQuestions + testStrategy

    // MARK: 답변 구조 (20)

    private static let answerStructure: [OPIcTip] = [
        OPIcTip(id: "structure-01", category: .answerStructure,
                text: "답을 시작할 때 결론 한 문장을 먼저 말하고, 그다음에 이유나 예를 붙여 보세요."),
        OPIcTip(id: "structure-02", category: .answerStructure,
                text: "말하기 전에 2초만 써서 말할 순서 두 개를 정해두면 중간에 길을 잃지 않아요."),
        OPIcTip(id: "structure-03", category: .answerStructure,
                text: "한 답변에 여러 주제를 넣기보다, 하나를 골라 조금 더 자세히 풀어보세요."),
        OPIcTip(id: "structure-04", category: .answerStructure,
                text: "\"예를 들면\"으로 구체적인 장면을 하나 붙이면 짧은 답변도 충분히 채워져요."),
        OPIcTip(id: "structure-05", category: .answerStructure,
                text: "마무리는 감상 한 문장이면 충분해요. 요약을 길게 만들지 않아도 괜찮아요."),
        OPIcTip(id: "structure-06", category: .answerStructure,
                text: "답이 너무 빨리 끝났다면 이유를 하나 덧붙이는 연습부터 해보세요."),
        OPIcTip(id: "structure-07", category: .answerStructure,
                text: "무엇 → 왜 → 그래서. 세 문장 뼈대를 몸에 익혀두면 어떤 질문에도 시작점이 생겨요."),
        OPIcTip(id: "structure-08", category: .answerStructure,
                text: "서론을 길게 끌지 말고 첫 문장부터 질문에 바로 답해 보세요."),
        OPIcTip(id: "structure-09", category: .answerStructure,
                text: "나열은 두세 개까지만. 개수를 늘리기보다 하나를 설명하는 편이 듣기 좋아요."),
        OPIcTip(id: "structure-10", category: .answerStructure,
                text: "말하다 방향이 꼬이면 \"쉽게 말하면\"으로 한 번 정리하고 이어가 보세요."),
        OPIcTip(id: "structure-11", category: .answerStructure,
                text: "시간 순서(그전에 → 그때 → 그 후에)는 가장 안전한 뼈대예요. 막힐 때 꺼내 쓰세요."),
        OPIcTip(id: "structure-12", category: .answerStructure,
                text: "이유를 말할 때 because만 반복하지 말고 so, that's why로도 연결해 보세요."),
        OPIcTip(id: "structure-13", category: .answerStructure,
                text: "첫 문장은 짧게, 두 번째 문장부터 길게. 시작이 가벼우면 긴장이 덜 실려요."),
        OPIcTip(id: "structure-14", category: .answerStructure,
                text: "답변에 감정 한 마디(좋았어요, 아쉬웠어요)를 넣으면 사실 나열이 이야기로 바뀌어요."),
        OPIcTip(id: "structure-15", category: .answerStructure,
                text: "질문의 핵심 단어를 그대로 한 번 쓰면서 답을 시작하면 주제에서 멀어지지 않아요."),
        OPIcTip(id: "structure-16", category: .answerStructure,
                text: "문장을 통째로 외워 붙이기보다, 뼈대만 외우고 살은 그때그때 붙이는 편이 자연스러워요."),
        OPIcTip(id: "structure-17", category: .answerStructure,
                text: "답이 길어질 것 같으면 \"두 가지를 말해볼게요\"처럼 먼저 지도를 그려 주세요."),
        OPIcTip(id: "structure-18", category: .answerStructure,
                text: "예시가 떠오르지 않으면 최근에 있었던 일을 그대로 쓰면 돼요. 특별하지 않아도 괜찮아요."),
        OPIcTip(id: "structure-19", category: .answerStructure,
                text: "끝을 흐리지 말고 문장 하나를 분명히 닫아 보세요. 마침이 또렷하면 정돈되어 들려요."),
        OPIcTip(id: "structure-20", category: .answerStructure,
                text: "같은 질문에 뼈대를 바꿔 두 번 답해 보면 한 가지 틀에 묶이지 않아요."),
    ]

    // MARK: 자연스러운 말하기 (20)

    private static let naturalSpeaking: [OPIcTip] = [
        OPIcTip(id: "speaking-01", category: .naturalSpeaking,
                text: "완벽한 문장을 만들려고 오래 멈추기보다, 짧은 문장을 자연스럽게 이어가 보세요."),
        OPIcTip(id: "speaking-02", category: .naturalSpeaking,
                text: "말이 막히면 침묵 대신 let me think처럼 짧게 시간을 벌고 다시 이어가면 돼요."),
        OPIcTip(id: "speaking-03", category: .naturalSpeaking,
                text: "어려운 단어를 찾느라 멈추기보다, 아는 쉬운 단어 두세 개로 풀어 설명해 보세요."),
        OPIcTip(id: "speaking-04", category: .naturalSpeaking,
                text: "문장 끝을 올렸다 내렸다 하며 억양을 주면 같은 내용도 훨씬 자연스럽게 들려요."),
        OPIcTip(id: "speaking-05", category: .naturalSpeaking,
                text: "녹음을 다시 들으며 \"내가 실제로 이렇게 말하나?\" 한 번만 확인해도 어색한 문장이 줄어요."),
        OPIcTip(id: "speaking-06", category: .naturalSpeaking,
                text: "속도를 올리는 것보다 또박또박 이어 말하는 쪽이 알아듣기 쉬워요."),
        OPIcTip(id: "speaking-07", category: .naturalSpeaking,
                text: "문장 사이의 짧은 쉼은 실수가 아니에요. 숨 쉬는 자리를 정해두면 오히려 안정적으로 들려요."),
        OPIcTip(id: "speaking-08", category: .naturalSpeaking,
                text: "and와 so만 반복된다면 하나만 바꿔 보세요. 전부 고치지 않아도 인상이 달라져요."),
        OPIcTip(id: "speaking-09", category: .naturalSpeaking,
                text: "말하다 틀린 걸 알아차렸다면 처음부터 다시 하지 말고 그 부분만 고쳐 이어가세요."),
        OPIcTip(id: "speaking-10", category: .naturalSpeaking,
                text: "자주 쓰는 표현 다섯 개를 정해 입에 붙여 두면, 긴장해도 첫 문장이 나와요."),
        OPIcTip(id: "speaking-11", category: .naturalSpeaking,
                text: "머릿속에서 한국어 문장을 완성한 뒤 번역하면 느려져요. 짧은 영어 문장부터 바로 시작해 보세요."),
        OPIcTip(id: "speaking-12", category: .naturalSpeaking,
                text: "발음보다 리듬이 먼저예요. 강조할 단어 하나만 정해서 조금 세게 말해 보세요."),
        OPIcTip(id: "speaking-13", category: .naturalSpeaking,
                text: "하루 3분이라도 소리 내어 말하면 시험장에서 내 목소리가 낯설지 않아요."),
        OPIcTip(id: "speaking-14", category: .naturalSpeaking,
                text: "um, you know가 많게 느껴지면 없애려 애쓰기보다 문장을 짧게 끊어 보세요."),
        OPIcTip(id: "speaking-15", category: .naturalSpeaking,
                text: "아는 표현을 정확히 쓰는 편이, 외운 고급 표현을 어색하게 쓰는 것보다 편하게 들려요."),
        OPIcTip(id: "speaking-16", category: .naturalSpeaking,
                text: "말하기 전에 첫 다섯 단어만 정해두면 시작이 훨씬 가벼워져요."),
        OPIcTip(id: "speaking-17", category: .naturalSpeaking,
                text: "원어민 문장을 통째로 외우기보다, 구조 하나를 골라 내 이야기로 바꿔 보세요."),
        OPIcTip(id: "speaking-18", category: .naturalSpeaking,
                text: "혼잣말로 오늘 한 일을 영어로 중계해 보면 실전 감각이 붙어요."),
        OPIcTip(id: "speaking-19", category: .naturalSpeaking,
                text: "목소리가 작아지면 문장 끝이 뭉개져요. 평소보다 조금 크게 말하는 연습을 해보세요."),
        OPIcTip(id: "speaking-20", category: .naturalSpeaking,
                text: "어색한 표현이 나와도 사과하지 말고 그대로 이어가세요. 흐름이 끊기지 않는 편이 나아요."),
    ]

    // MARK: 경험 질문 (15)

    private static let experience: [OPIcTip] = [
        OPIcTip(id: "experience-01", category: .experience,
                text: "과거 경험은 언제 → 무엇을 했는지 → 왜 기억에 남는지 순서로 정리하면 흐름을 만들기 쉬워요."),
        OPIcTip(id: "experience-02", category: .experience,
                text: "특별한 사건이 없어도 괜찮아요. 평범한 하루를 구체적으로 말하는 편이 더 자연스러워요."),
        OPIcTip(id: "experience-03", category: .experience,
                text: "경험 이야기에는 사람 한 명을 등장시켜 보세요. 누구와 함께였는지가 들어가면 장면이 살아나요."),
        OPIcTip(id: "experience-04", category: .experience,
                text: "시제가 흔들릴 것 같으면 yesterday, last summer처럼 시간 표현을 먼저 말하고 시작하세요."),
        OPIcTip(id: "experience-05", category: .experience,
                text: "기억이 정확하지 않아도 돼요. 편하게 말할 수 있는 버전으로 정리해 두세요."),
        OPIcTip(id: "experience-06", category: .experience,
                text: "결과만 말하지 말고 그때의 기분을 한 문장 넣으면 이야기가 밋밋해지지 않아요."),
        OPIcTip(id: "experience-07", category: .experience,
                text: "자주 나오는 주제(여행, 외식, 영화)는 실제 경험을 하나씩만 골라 두면 준비가 끝나요."),
        OPIcTip(id: "experience-08", category: .experience,
                text: "문제가 있었던 경험은 상황 → 대처 → 결과 세 칸으로 나눠 두면 여러 질문에 꺼내 쓰기 좋아요."),
        OPIcTip(id: "experience-09", category: .experience,
                text: "\"처음으로 ~했던 때\"는 좋은 소재예요. 시작과 끝이 분명해서 이야기가 정리돼요."),
        OPIcTip(id: "experience-10", category: .experience,
                text: "여러 번 반복된 일은 시제가 섞이기 쉬워요. 한 번의 장면으로 좁혀 말해 보세요."),
        OPIcTip(id: "experience-11", category: .experience,
                text: "사소한 디테일 하나(날씨, 음식 이름)를 넣으면 답변이 구체적으로 들려요."),
        OPIcTip(id: "experience-12", category: .experience,
                text: "마무리는 \"그래서 지금도 가끔 생각나요\"처럼 현재와 연결하면 자연스러워요."),
        OPIcTip(id: "experience-13", category: .experience,
                text: "같은 경험도 질문에 따라 강조점을 바꿀 수 있어요. 소재를 늘리기보다 각도를 바꿔 보세요."),
        OPIcTip(id: "experience-14", category: .experience,
                text: "그때 오간 말을 그대로 옮기는 문장을 하나 넣으면 이야기에 생기가 생겨요."),
        OPIcTip(id: "experience-15", category: .experience,
                text: "경험 질문은 사실 확인이 아니라 이야기하기예요. 완벽한 기억보다 편한 전달이 먼저예요."),
    ]

    // MARK: 묘사·비교 (15)

    private static let descriptionComparison: [OPIcTip] = [
        OPIcTip(id: "description-01", category: .descriptionComparison,
                text: "비교 질문에서는 두 대상을 각각 길게 설명하기보다 가장 큰 차이 한두 가지부터 말해보세요."),
        OPIcTip(id: "description-02", category: .descriptionComparison,
                text: "장소는 큰 것에서 작은 것 순서로 옮겨가며 묘사하면 듣는 사람이 그림을 그리기 쉬워요."),
        OPIcTip(id: "description-03", category: .descriptionComparison,
                text: "모든 걸 다 묘사하지 않아도 돼요. 가장 눈에 띄는 특징 두 개면 충분해요."),
        OPIcTip(id: "description-04", category: .descriptionComparison,
                text: "\"A는 이런데 B는 저래요\"처럼 문장 짝을 맞추면 비교가 정리되어 들려요."),
        OPIcTip(id: "description-05", category: .descriptionComparison,
                text: "크기, 분위기, 사람 수처럼 기준을 먼저 정하고 비교하면 말이 흩어지지 않아요."),
        OPIcTip(id: "description-06", category: .descriptionComparison,
                text: "색이나 소리 같은 감각 표현을 하나만 넣어도 묘사가 훨씬 선명해져요."),
        OPIcTip(id: "description-07", category: .descriptionComparison,
                text: "예전과 지금을 비교할 때는 시제를 확실히 나눠 주세요. used to로 시작하면 편해요."),
        OPIcTip(id: "description-08", category: .descriptionComparison,
                text: "묘사가 어렵다면 그 공간에서 내가 주로 무엇을 하는지 말하는 것으로 대신해도 돼요."),
        OPIcTip(id: "description-09", category: .descriptionComparison,
                text: "좋고 나쁨을 가리기보다 어떻게 다른지를 설명하는 쪽이 말하기 쉽고 자연스러워요."),
        OPIcTip(id: "description-10", category: .descriptionComparison,
                text: "사람을 묘사할 때는 외모보다 성격과 함께한 일을 말하면 이야기가 이어져요."),
        OPIcTip(id: "description-11", category: .descriptionComparison,
                text: "숫자를 하나 넣으면(10분 거리, 세 명) 설명이 갑자기 구체적으로 들려요."),
        OPIcTip(id: "description-12", category: .descriptionComparison,
                text: "비교의 마지막에는 내가 어느 쪽을 더 좋아하는지 한 문장으로 정리해 보세요."),
        OPIcTip(id: "description-13", category: .descriptionComparison,
                text: "It's kind of ~, It looks like ~처럼 흐릿한 표현도 묘사에서는 충분히 쓸 만해요."),
        OPIcTip(id: "description-14", category: .descriptionComparison,
                text: "변화 이야기는 전에는 → 지금은 → 앞으로는 순서로 짧게 세 문장이면 돼요."),
        OPIcTip(id: "description-15", category: .descriptionComparison,
                text: "내 방이나 동네를 미리 한 번 영어로 묘사해 두면 비슷한 질문 여러 개를 함께 대비할 수 있어요."),
    ]

    // MARK: 롤플레이 (10)

    private static let rolePlay: [OPIcTip] = [
        OPIcTip(id: "roleplay-01", category: .rolePlay,
                text: "롤플레이는 인사와 상황 한 문장으로 시작하면 흐름이 자연스럽게 잡혀요."),
        OPIcTip(id: "roleplay-02", category: .rolePlay,
                text: "질문을 만들어야 할 때는 궁금한 것 세 가지를 미리 정해두고 하나씩 물어보세요."),
        OPIcTip(id: "roleplay-03", category: .rolePlay,
                text: "정보를 물을 때는 언제, 얼마, 어디를 축으로 삼으면 질문이 쉽게 나와요."),
        OPIcTip(id: "roleplay-04", category: .rolePlay,
                text: "문제 상황에서는 상황 설명 → 원하는 것 → 대안 제안 순서가 편해요."),
        OPIcTip(id: "roleplay-05", category: .rolePlay,
                text: "상대가 앞에 있다고 생각하고 말하면 톤이 훨씬 자연스러워져요."),
        OPIcTip(id: "roleplay-06", category: .rolePlay,
                text: "전화 상황이라면 Hi, I'm calling about ~처럼 목적을 먼저 밝히고 시작하세요."),
        OPIcTip(id: "roleplay-07", category: .rolePlay,
                text: "부탁할 때는 이유를 한 문장 붙이면 요청이 훨씬 자연스럽게 들려요."),
        OPIcTip(id: "roleplay-08", category: .rolePlay,
                text: "대안을 제안할 때 쓸 표현 하나(Would it be possible to ~?)만 준비해도 든든해요."),
        OPIcTip(id: "roleplay-09", category: .rolePlay,
                text: "모르는 정보는 상황에 맞게 지어 말해도 괜찮아요. 롤플레이는 사실 확인이 아니에요."),
        OPIcTip(id: "roleplay-10", category: .rolePlay,
                text: "마지막에 감사 인사를 한 문장 덧붙이면 대화가 깔끔하게 닫혀요."),
    ]

    // MARK: 돌발 질문 (10)

    private static let unexpectedQuestions: [OPIcTip] = [
        OPIcTip(id: "unexpected-01", category: .unexpectedQuestions,
                text: "예상 못 한 질문은 아는 쪽으로 좁혀서 답해 보세요. 전부 다 다루지 않아도 괜찮아요."),
        OPIcTip(id: "unexpected-02", category: .unexpectedQuestions,
                text: "처음 듣는 주제라도 \"저는 잘 안 하지만 주변에는\"처럼 각도를 바꾸면 할 말이 생겨요."),
        OPIcTip(id: "unexpected-03", category: .unexpectedQuestions,
                text: "질문을 반쯤 놓쳤다면 들은 단어를 중심으로 답을 시작하면서 방향을 잡아 보세요."),
        OPIcTip(id: "unexpected-04", category: .unexpectedQuestions,
                text: "낯선 주제일수록 짧은 문장으로 천천히. 무리해서 길게 늘리지 않아도 돼요."),
        OPIcTip(id: "unexpected-05", category: .unexpectedQuestions,
                text: "사회적인 주제에 정답은 없어요. 내 생각 하나와 이유 하나면 충분해요."),
        OPIcTip(id: "unexpected-06", category: .unexpectedQuestions,
                text: "모르겠다고만 끝내지 말고, 그렇게 말한 뒤 관련된 내 경험으로 이어가 보세요."),
        OPIcTip(id: "unexpected-07", category: .unexpectedQuestions,
                text: "돌발 대비는 소재를 외우기보다 어떤 주제에도 쓸 수 있는 뼈대 하나를 갖는 쪽이 효율적이에요."),
        OPIcTip(id: "unexpected-08", category: .unexpectedQuestions,
                text: "최근 뉴스나 주변의 변화 한 가지를 영어로 짧게 말해 두면 여러 주제에 활용할 수 있어요."),
        OPIcTip(id: "unexpected-09", category: .unexpectedQuestions,
                text: "어려운 질문일수록 첫 문장을 아주 단순하게 시작해 보세요. 두 번째 문장부터 편해져요."),
        OPIcTip(id: "unexpected-10", category: .unexpectedQuestions,
                text: "답하다 막히면 예를 하나 들어보세요. 예시는 막힌 흐름을 다시 여는 가장 쉬운 방법이에요."),
    ]

    // MARK: 시험 운영·멘탈 (10)

    private static let testStrategy: [OPIcTip] = [
        OPIcTip(id: "strategy-01", category: .testStrategy,
                text: "시작 전 마이크 테스트에서 평소보다 조금 크게 말해 보세요. 첫 문항이 편해져요."),
        OPIcTip(id: "strategy-02", category: .testStrategy,
                text: "자기소개는 짧게. 뒤 문항에서 쓸 이야기를 남겨 두는 편이 좋아요."),
        OPIcTip(id: "strategy-03", category: .testStrategy,
                text: "한 문항이 아쉬웠다고 다음 문항까지 흔들 필요는 없어요. 문항마다 새로 시작하면 돼요."),
        OPIcTip(id: "strategy-04", category: .testStrategy,
                text: "난이도 선택은 평소 연습하던 수준에 맞추는 편이 안정적이에요."),
        OPIcTip(id: "strategy-05", category: .testStrategy,
                text: "시험 전날은 새 표현을 외우기보다 이미 아는 문장을 소리 내어 정리해 보세요."),
        OPIcTip(id: "strategy-06", category: .testStrategy,
                text: "배경 설문은 실제로 익숙한 항목으로 고르면 말할 거리를 만들기 쉬워요."),
        OPIcTip(id: "strategy-07", category: .testStrategy,
                text: "말이 빨라진다고 느끼면 한 문장을 끝내고 한 번 숨을 쉬어 보세요."),
        OPIcTip(id: "strategy-08", category: .testStrategy,
                text: "시간이 남았다고 억지로 채우기보다, 할 말을 마쳤으면 자연스럽게 끝내도 괜찮아요."),
        OPIcTip(id: "strategy-09", category: .testStrategy,
                text: "연습할 때 실전과 비슷한 길이로 말해 보면 시험장에서 체감 시간이 낯설지 않아요."),
        OPIcTip(id: "strategy-10", category: .testStrategy,
                text: "긴장은 없애기보다 안고 가는 편이 쉬워요. 첫 문장만 준비해 두면 나머지는 따라와요."),
    ]
}
