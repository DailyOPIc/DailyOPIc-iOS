# App Review notes — DailyOPIc 2.3.0

App Store Connect › 앱 심사 정보 › 메모에 아래 영문을 붙여 넣는다.

---

DailyOPIc helps Korean learners practice for the OPIc English speaking test.

In 2.3.0 we rebuilt the study screens with web technology so that iPhone and web share one up-to-date experience. The app still relies on native iOS features for everything beyond drawing the screens:

- Speaking practice records the user's voice through the microphone and transcribes it with iOS speech recognition. Users can then request AI feedback on their answers.
- Sign-in is native. Every user starts with an anonymous account, and can link Sign in with Apple or Google in Menu (☰) › 계정 · 로그인. Account deletion is available on the same screen and revokes the Sign in with Apple token.
- Subscriptions (Basic / Plus / Pro) are sold only through In-App Purchase via StoreKit/RevenueCat. Menu (☰) › 요금제 opens the native purchase screen. The app has no external payment links and no purchase steering.
- Ads use the native Google Mobile Ads SDK, after UMP consent and the App Tracking Transparency prompt. Free users see a native banner under the tab bar, and can watch a rewarded ad for one extra daily token (the coin "+" button at the top).

How to test:
1. Launch the app. No login is required (an anonymous account is created automatically).
2. Pick a level and 3 or more interests. Today's question set then appears.
3. Tap a question, tap 말하기 시작, speak in English, then tap 답변 완료 to see quick feedback.
4. Tabs: 모의고사 (15-question mock test), 오픽게임 (word games), 활동 (activity calendar).
5. Menu (☰) › 요금제 shows the IAP subscriptions. Menu (☰) › 계정 · 로그인 shows account linking and deletion.

Demo account: not required.
