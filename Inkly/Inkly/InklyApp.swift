import SwiftUI

@main
struct InklyApp: App {
    init() {
        let dict = Bundle.main.infoDictionary ?? [:]
        print("🔎 Info.plist keys:", dict.keys.sorted())
        print("🔎 INKLY_BASE_URL =", dict["INKLY_BASE_URL"] as Any)
        print("🔎 INKLY_API_KEY  =", dict["INKLY_API_KEY"] as Any)
        print("🔎 Bundle id      =", Bundle.main.bundleIdentifier ?? "nil")
        #if DEBUG
        print("🔎 Running in previews =", ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1")
        #endif
    }
    var body: some Scene { WindowGroup { UploadView() } }
}
