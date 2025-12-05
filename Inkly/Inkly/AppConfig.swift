import SwiftUI

enum AppConfig {
    static var baseURL: URL = {
        // 프리뷰일 때는 더미 URL 반환
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return URL(string: "https://example.com")!
        }
        #endif

        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: "INKLY_BASE_URL") as? String,
            let url = URL(string: raw)
        else {
            fatalError("INKLY_BASE_URL missing or invalid")
        }
        return url
    }()

    static var apiKey: String = {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return "dev-key"
        }
        #endif
        return (Bundle.main.object(forInfoDictionaryKey: "INKLY_API_KEY") as? String) ?? "dev-key"
    }()
}
