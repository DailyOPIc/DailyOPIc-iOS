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
        view.rootViewController = UIApplication.shared.topViewController
        if let unitID = AppConfiguration.bannerAdUnitID {
            view.adUnitID = unitID
            view.load(Request())
        } else {
            print("[DailyOPIc][Ads] banner ad unit ID is missing")
        }
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
