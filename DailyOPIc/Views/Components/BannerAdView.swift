import SwiftUI

#if canImport(GoogleMobileAds)
import GoogleMobileAds

struct BannerAdView: View {
    @EnvironmentObject private var ads: AdService

    var body: some View {
        Group {
            if ads.canRequestAds {
                GoogleBannerView()
            } else {
                Color.clear
            }
        }
    }
}

private struct GoogleBannerView: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let view = BannerView(adSize: AdSizeBanner)
        #if DEBUG
        view.adUnitID = "ca-app-pub-3940256099942544/2435281174"
        #else
        view.adUnitID = "ca-app-pub-5460686409666356/5124626013"
        #endif
        view.load(Request())
        return view
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        uiView.rootViewController = UIApplication.shared.topViewController
    }
}

private extension UIApplication {
    var topViewController: UIViewController? {
        connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?
            .rootViewController
    }
}
#else
struct BannerAdView: View {
    var body: some View { EmptyView() }
}
#endif
