# DailyOPIc iOS

SwiftUI/iOS 17 앱입니다. 번들 ID는 기존 앱 업데이트용 `com.mark.opicmobile`이며 학습 기록,
목표 등급, Background Survey, 모의고사 draft는 SwiftData/UserDefaults에만 저장합니다.

## 실행

1. 루트 `DailyOPIc-BE`에서 개발 서버를 `uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload`로 실행합니다.
2. `DailyOPIc.xcodeproj`를 열고 iOS 17 이상 시뮬레이터 또는 실제 기기를 선택합니다.
3. Debug는 `Config/Debug.xcconfig`의 `DAILYOPIC_API_BASE_URL`과 운영 AdMob Unit ID를 사용합니다. 광고 테스트는 Scheme 환경변수의 test device ID로만 분리합니다.

## 실제 iPhone 무선 디버깅 API 주소

실제 iPhone에서 `127.0.0.1`은 Mac이 아니라 iPhone 자기 자신입니다. iPhone 핫스팟 네트워크에서 Mac의 FastAPI 서버에 붙을 때는 `http://<Mac의 핫스팟 IP>:8000` 형식이어야 합니다.

1. Mac에서 서버를 외부 인터페이스로 엽니다.

```bash
cd ../DailyOPIc-BE
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

2. Mac의 현재 핫스팟 IP를 확인합니다.

```bash
ipconfig getifaddr en0
```

현재 확인한 값은 `172.20.10.2`입니다. 네트워크를 다시 연결하면 바뀔 수 있습니다.

3. `Config/Debug.xcconfig`에서 아래 값을 Mac IP로 바꿉니다.

```xcconfig
DAILYOPIC_DEBUG_SERVER_HOST = 172.20.10.2
DAILYOPIC_DEBUG_SERVER_PORT = 8000
```

또는 Xcode에서 `Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables`에 다음 중 하나를 추가해 Debug 실행마다 덮어쓸 수 있습니다.

```text
DAILYOPIC_API_BASE_URL = http://172.20.10.2:8000
```

```text
DAILYOPIC_DEBUG_SERVER_HOST = 172.20.10.2
DAILYOPIC_DEBUG_SERVER_PORT = 8000
```

앱 시작 로그에서 `[DailyOPIc][API] baseURL=... source=...`를 확인하면 실제로 어떤 주소가 선택됐는지 볼 수 있습니다.

## iPhone 핫스팟 연결 확인

1. Mac과 iPhone이 같은 iPhone 핫스팟 네트워크에 있는지 확인합니다.
2. Mac에서 `uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload`가 실행 중인지 확인합니다.
3. iPhone Safari에서 `http://<Mac IP>:8000/health` 또는 `http://<Mac IP>:8000/docs`를 엽니다.
4. Safari에서 열리면 Xcode로 앱을 Debug 실행하고 로그의 `[DailyOPIc][API] baseURL=`가 같은 IP인지 확인합니다.
5. 앱에서 Practice 화면 진입 시 FastAPI 로그에 `/v1/usage`, `/v1/question-sets/practice` 요청이 찍히는지 확인합니다.

## Release 전에 필요한 외부 값

- Firebase Console에서 `com.mark.opicmobile`의 익명 Auth와 App Check/App Attest를 활성화합니다.
- `GoogleService-Info.plist`를 `DailyOPIc/Resources/Firebase/`에 추가합니다.
- `Config/Release.xcconfig`의 `DAILYOPIC_API_BASE_URL`을 실제 Cloud Run HTTPS URL로 교체합니다. Release에는 로컬 IP를 넣지 않습니다.
- AdMob Console에서 운영 배너 Unit ID가 `ca-app-pub-5460686409666356/5124626013`인지 확인합니다.
- AdMob Console에서 운영 리워드 Unit ID가 `ca-app-pub-5460686409666356/7091483531`인지 확인합니다.
- AdMob Console > 개인정보 보호 및 메시지에서 UMP 동의 메시지를 생성하고 게시합니다.
- AdMob Console에 개인정보처리방침 URL을 등록합니다.
- App Store 등록 후 AdMob 앱과 App Store 앱을 연결합니다.
- Rewarded SSV callback은 Cloud Run 배포 후 `https://<cloud-run>/v1/admob/ssv`로 설정합니다.

OpenAI 키와 Firestore 관리자 권한은 iOS 앱에 포함하지 않습니다. Release에서 Firebase plist가
없거나 App Check 토큰을 얻지 못하면 인증 단계에서 앱이 오류를 표시합니다.

## AdMob과 UMP 설정

광고 Unit ID와 개인정보처리방침 URL은 `Config/Debug.xcconfig`, `Config/Release.xcconfig`에서
`Info.plist`로 주입되고 `AppConfiguration`에서 읽습니다.

```xcconfig
GAD_BANNER_AD_UNIT_ID = ca-app-pub-5460686409666356/5124626013
GAD_REWARDED_AD_UNIT_ID = ca-app-pub-5460686409666356/7091483531
DAILYOPIC_PRIVACY_POLICY_URL = https:/$()/battle-princess-097.notion.site/2d05d51fd9518084a95ce3b9193eb5ed?source=copy_link
```

Debug와 Release 모두 운영 광고 Unit ID를 사용합니다. Debug에서 실제 광고 노출/클릭으로 인한
무효 트래픽을 피하려면 Xcode의 `Product > Scheme > Edit Scheme > Run > Arguments >
Environment Variables`에 광고 테스트 디바이스 ID를 넣습니다.

```text
GAD_TEST_DEVICE_IDS = <Google Mobile Ads 콘솔 로그의 테스트 디바이스 ID>
```

UMP 동의 메시지 테스트는 별도 환경변수를 사용합니다.

```text
UMP_DEBUG_TEST_DEVICE_IDS = <UMP 콘솔 로그의 테스트 디바이스 ID>
```

`GAD_TEST_DEVICE_IDS`는 광고 요청을 테스트 광고로 처리하기 위한 값이고,
`UMP_DEBUG_TEST_DEVICE_IDS`는 동의 메시지 디버그 geography와 메시지 표시 테스트용 값입니다.
두 값을 혼용하지 않습니다. 이 두 환경변수는 Debug 코드에서만 읽으며, `Info.plist`나 Release
xcconfig에는 넣지 않습니다.

앱 시작 로그에서 다음 항목을 확인합니다.

```text
[DailyOPIc][Ads] bannerAdUnitID=... rewardedAdUnitID=...
[DailyOPIc][Privacy] privacyPolicyURL=...
[DailyOPIc][UMP] consent info updated...
[DailyOPIc][UMP] canRequestAds=...
```

Release 빌드 전에는 `rg "ca-app-pub-3940256099942544|GAD_TEST_DEVICE_IDS|UMP_DEBUG_TEST_DEVICE_IDS"`
결과를 확인해 테스트 광고 Unit ID와 테스트 디바이스 설정이 앱 번들 설정에 남지 않았는지 봅니다.

## 검증

```bash
xcodebuild -project DailyOPIc.xcodeproj -scheme DailyOPIc \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build-for-testing
```

STT, 녹음, UMP, 배너와 리워드 광고는 실제 기기에서 최종 확인해야 합니다.
