import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// OS ごとに違うところを、ここ1か所にまとめる。
/// **画面の側に `#if` を散らさない。**散らすと、どちらかの OS だけ直し忘れる
enum Platform {

    /// 通知の設定を開く。iOS はこのアプリの設定、Mac は「通知」の設定
    static func openNotificationSettings() {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #else
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        if let url { NSWorkspace.shared.open(url) }
        #endif
    }
}

extension View {
    /// `navigationBarTitleDisplayMode` は iOS にしか無い
    @ViewBuilder
    func compactNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
