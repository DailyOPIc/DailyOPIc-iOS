import Foundation

/// 시험일 안내 한 줄. 공식 규정과 DailyOPIc 권장을 **같은 타입**으로 담되,
/// 어느 목록에 들어 있는지로 성격이 갈린다(`officialRules` vs `dailyOPIcTips`).
struct ExamGuideItem: Identifiable, Hashable, Sendable {
    let title: String
    let detail: String
    let symbol: String

    var id: String { title }
}

/// OPIc 시험 당일 안내(P12). 정적·로컬·오프라인이다 —
/// Remote Config도, 백엔드도, 런타임 크롤링도 쓰지 않는다.
///
/// 여기 문장은 두 종류뿐이고 절대 섞지 않는다.
/// - `officialRules`: OPIc 공식 안내에서 확인한 **규정**. 임의로 바꾸지 않는다.
/// - `dailyOPIcTips`: DailyOPIc의 **권장**. 규정처럼 보이게 쓰지 않는다.
///
/// 공식 출처(2026-08-20 확인):
/// - 수험자 가이드: https://www.opic.or.kr/opics/servlet/controller.opic.site.guide.GuideServlet?p_process=move-exam-guide
/// - 시험관리규정: https://www.opic.or.kr/opics/servlet/controller.opic.site.applyinfor.ActflTestRuleServlet?p_process=move-actfl_test_rule
///
/// 규정은 바뀔 수 있다. 앱이 규정을 실시간으로 받아오지 않으므로
/// 카드 아래에 공식 안내를 한 번 더 확인해 달라는 문장을 항상 함께 둔다.
enum OPIcExamDayGuide {
    static let sectionTitle = "OPIc 시험일"
    static let officialTitle = "공식 확인사항"
    static let tipsTitle = "DailyOPIc 시험 당일 팁"

    /// 공식 안내를 요약한 문장들. 규정 원문을 그대로 붙이지 않되 사실을 바꾸지도 않는다.
    static let officialRules: [ExamGuideItem] = [
        ExamGuideItem(
            title: "규정 신분증",
            detail: """
            인정되는 규정 신분증을 지참해야 응시할 수 있어요. \
            모바일 신분증은 법적 효력이 있는 서비스가 정상 작동하는 상태만 인정되고, \
            사본·캡처·촬영본은 인정되지 않아요. 훼손돼 신원 확인이 어려우면 거부될 수 있어요.
            """,
            symbol: "person.text.rectangle"
        ),
        ExamGuideItem(
            title: "입실 시간",
            detail: """
            시험 시작 10분 전 감독관 안내에 따라 1차 신분 확인을 거쳐 입실해요. \
            지각하면 응시할 수 없고, 당일 연기나 환불도 되지 않아요.
            """,
            symbol: "clock"
        ),
        ExamGuideItem(
            title: "제한 물품",
            detail: """
            필기도구를 책상 위에 두거나 사용하면 규정 위반이에요. \
            휴대폰·스마트워치 등 전자기기에서 벨이나 진동이 울려도 마찬가지예요. \
            교재·쪽지·메모 같은 참고 자료는 소지만 해도 부정행위로 처리돼요. \
            식음료를 비롯한 개인 물품은 시험장·감독관 안내에 따라 정리해요.
            """,
            symbol: "bag.badge.minus"
        ),
        ExamGuideItem(
            title: "문제 메모·녹음 금지",
            detail: """
            시험 문제나 단어를 메모하거나 녹음하는 행위, 문제를 외부로 알리는 행위는 \
            저작권 침해로 처리돼요.
            """,
            symbol: "nosign"
        ),
        ExamGuideItem(
            title: "장비 이상",
            detail: """
            헤드셋·마이크·시험 화면 등에 이상이 있으면 직접 조작하기보다 \
            감독관에게 바로 알려 조치를 받아요.
            """,
            symbol: "exclamationmark.bubble"
        ),
        ExamGuideItem(
            title: "응시 유형별 확인",
            detail: """
            학생·외국인 등 응시 유형에 따라 인정되는 신분증이 다르고, \
            특정 응시 유형은 추가 신분확인 서류가 필요할 수 있어요.
            """,
            symbol: "person.2"
        )
    ]

    static let acceptedIDTitle = "일반 응시자 규정 신분증 예시"

    /// 접힌 채로 둔다. 전체 신분증 표를 카드에 펼쳐 두면 정작 볼 것이 안 보인다.
    /// "예:"로 시작하는 이유는 이 목록이 전부가 아니기 때문이다.
    static let acceptedIDExamples = """
    예: 주민등록증, 자동차운전면허증, 기간 만료 전의 여권, 공무원증, \
    장애인 복지카드, 국가보훈등록증
    """

    /// DailyOPIc 권장 4~6개. 점수·합격을 약속하지 않고, 공식 규정인 척하지 않는다.
    static let dailyOPIcTips: [String] = [
        "시험장 위치와 이동 시간을 전날 미리 확인해 두면 당일에 덜 헤매요.",
        "집에서 나서기 전에 규정 신분증을 실제로 챙겼는지 한 번 더 확인해요.",
        "공식 입실 시간보다 조금 더 여유 있게 도착하면 신분 확인 줄에서 급하지 않아요.",
        "직전에는 새로운 표현을 무리하게 외우기보다 익숙한 답변 흐름을 가볍게 정리해요.",
        "휴대폰·가방 같은 개인 물품은 감독관 안내에 따라 미리 정리해 두면 편해요.",
        "한 문제를 아쉽게 답했더라도 다음 문제에 집중해요."
    ]

    /// 규정은 바뀔 수 있고 앱은 이를 자동으로 받아오지 않는다. 그 사실을 감추지 않는다.
    static let footer = "안내는 참고용이에요. 응시 전 OPIc 공식 안내를 한 번 더 확인해 주세요."

    static let officialLinkTitle = "OPIc 공식 안내 확인"
    /// 사용자가 직접 눌렀을 때만 열린다. 앱이 이 주소를 자동으로 부르지 않는다.
    static let officialLink = URL(
        string: "https://www.opic.or.kr/opics/servlet/controller.opic.site.guide.GuideServlet?p_process=move-exam-guide"
    )!
}
