# Firebase iOS 설정

Firebase Console에서 번들 ID `com.mark.opicmobile` 앱을 등록한 뒤 다운로드한
`GoogleService-Info.plist`를 이 디렉터리에 추가하세요.

- Authentication에서 익명 로그인을 활성화합니다.
- App Check에서 App Attest를 등록합니다.
- Apple Developer의 Identifiers에서 `com.mark.opicmobile` explicit App ID에 App Attest
  capability를 활성화하고, wildcard가 아닌 새 provisioning profile을 내려받습니다.
- Firebase App Check는 App Attest sandbox attestation을 허용하지 않으므로
  `DailyOPIc.entitlements`의 App Attest environment는 `production`으로 둡니다.
- 실제 기기에서는 Debug/Release 모두 App Attest provider를 사용합니다.
- 시뮬레이터에서는 App Attest를 사용할 수 없으므로 App Check debug provider를 사용합니다.
  Xcode 로그의 App Check debug token을 Firebase Console에 등록합니다.
- Firestore SDK는 iOS 앱에 넣지 않습니다. Firestore 접근은 `DailyOPIc-BE` 서버만 수행합니다.

plist가 없는 로컬 Debug 빌드는 `X-Debug-User-ID`로 개발 서버에 연결됩니다. Release 배포에는
반드시 Firebase plist가 필요합니다.
