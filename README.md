# DailyOPIc iOS

SwiftUI/iOS 17 앱입니다. 번들 ID는 기존 앱 업데이트용 `com.mark.opicmobile`이며 학습 기록,
목표 등급, Background Survey, 모의고사 draft는 SwiftData/UserDefaults에만 저장합니다.

## 실행

1. 루트 `DailyOPIc-BE`에서 개발 서버를 `uvicorn app.main:app --reload`로 실행합니다.
2. `DailyOPIc.xcodeproj`를 열고 iOS 17 이상 시뮬레이터 또는 실제 기기를 선택합니다.
3. Debug는 `http://127.0.0.1:8000`, Google 테스트 배너/리워드 광고를 사용합니다.

## Release 전에 필요한 외부 값

- Firebase Console에서 `com.mark.opicmobile`의 익명 Auth와 App Check/App Attest를 활성화합니다.
- `GoogleService-Info.plist`를 `DailyOPIc/Resources/Firebase/`에 추가합니다.
- Xcode Release의 `DAILYOPIC_API_BASE_URL`을 실제 Cloud Run HTTPS URL로 교체합니다.
- Xcode Release의 `GAD_REWARDED_AD_UNIT_ID`를 새로 만든 운영 리워드 Unit ID로 교체합니다.
- AdMob 리워드 SSV 콜백을 `https://<cloud-run>/v1/admob/ssv`로 설정합니다.
- UMP 메시지와 개인정보 처리방침을 AdMob Console에서 게시합니다.

OpenAI 키와 Firestore 관리자 권한은 iOS 앱에 포함하지 않습니다. Release에서 Firebase plist가
없거나 App Check 토큰을 얻지 못하면 인증 단계에서 앱이 오류를 표시합니다.

## 검증

```bash
xcodebuild -project DailyOPIc.xcodeproj -scheme DailyOPIc \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

STT, 녹음, UMP, 배너와 리워드 광고는 실제 기기에서 최종 확인해야 합니다.
