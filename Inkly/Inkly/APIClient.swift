import Foundation
import UIKit

// MARK: - Errors
enum APIError: Error, LocalizedError {
    case invalidImage
    case badResponse(status: Int, body: String)
    case serverMessage(_ msg: String)
    case invalidURL(_ s: String)
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "PNG 변환 실패"
        case .badResponse(let status, let body): return "HTTP \(status): \(body)"
        case .serverMessage(let m): return m
        case .invalidURL(let s): return "잘못된 URL: \(s)"
        }
    }
}

// MARK: - DTOs used by APIClient
struct AnalyzeResponse: Decodable {
    let ok: Bool
    let metrics: [String: Double]?
    let analyzeType: String?   // ⭐ 추가
    let error: String?
}
struct UploadResponse: Decodable {
    let ok: Bool
    let filename: String?
    let jobId: String?
    let error: String?
}
struct GenerateResponse: Decodable {
    let ok: Bool
    let jobId: String?
    let state: String?      // "running" / "done" (보통 running)
    let error: String?
}

struct StatusResponse: Decodable {
    let ok: Bool
    let state: String?          // "none" / "running" / "done" / "error"
    let representative: String? // done일 때 경로
    let error: String?
}
struct ReanalyzeResponse: Decodable {
    let ok: Bool
    let metrics: [String: Double]?
    let error: String?
    let practice: String?
    let analyzeType: String?   // ⭐️ 추가
}

final class APIClient {
    static let shared = APIClient()
    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 60 * 30
        cfg.timeoutIntervalForResource = 60 * 30
        session = URLSession(configuration: cfg)
    }
    private let session: URLSession


    // MARK: - Request builder
    private func makeRequest(path: String, method: String = "GET", contentType: String? = nil) throws -> URLRequest {
        let url = AppConfig.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 60 * 30
        req.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        if let ct = contentType { req.setValue(ct, forHTTPHeaderField: "Content-Type") }
        return req
    }
    
    func url(path: String) -> URL {
        AppConfig.baseURL.appendingPathComponent(path)
    }

    // MARK: - Centralized sender
    @discardableResult
    private func send(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        print("➡️ \(req.httpMethod ?? "GET") \(req.url?.absoluteString ?? "")")
        if let headers = req.allHTTPHeaderFields { print("   headers:", headers) }
        if let body = req.httpBody { print("   body.bytes:", body.count) }

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw APIError.invalidURL("응답 형식이 HTTP가 아님")
        }

        let text = String(data: data, encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
        print("⬅️ status:", http.statusCode)
        print("⬅️ body  :", text)

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse(status: http.statusCode, body: text)
        }
        return (data, http)
    }

    // MARK: 1️⃣ 업로드 (multipart/form-data)
    func uploadPNG(_ data: Data, filename: String = "hand.png") async throws -> UploadResponse {
        guard filename.lowercased().hasSuffix(".png") else { throw APIError.invalidImage }

        let boundary = "Inkly-\(UUID().uuidString)"
        var req = try makeRequest(path: "upload", method: "POST",
                                  contentType: "multipart/form-data; boundary=\(boundary)")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (d, _) = try await send(req)
        let decoded = try JSONDecoder().decode(UploadResponse.self, from: d)
        if decoded.ok == false {
            throw APIError.serverMessage(decoded.error ?? "upload failed")
        }
        return decoded
    }

    // MARK: 2️⃣ 생성
    // MARK: 2️⃣ 생성 (비동기 시작)
    func generate(filename: String,
                  lambdas: [Double] = [0.2,0.4,0.6,0.8,1.0],
                  jobId: String) async throws -> GenerateResponse {
        var req = try makeRequest(path: "generate", method: "POST", contentType: "application/json")
        let body: [String: Any] = ["filename": filename, "lambdas": lambdas, "jobId": jobId]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (d, _) = try await send(req)
        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: d)
        if decoded.ok == false {
            throw APIError.serverMessage(decoded.error ?? "generate failed")
        }
        return decoded        // 여기서는 representative 없음
    }
    
    // MARK: 2-1️⃣ 상태 조회 (polling 용)
    func status(jobId: String) async throws -> StatusResponse {
        // GET /status?jobId=...
        let urlWithQuery = AppConfig.baseURL
            .appendingPathComponent("status")    // 서버에 /status 구현했다고 가정
        var comps = URLComponents(url: urlWithQuery, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "jobId", value: jobId)]

        guard let finalURL = comps.url else {
            throw APIError.invalidURL("status url")
        }

        var req = URLRequest(url: finalURL)
        req.httpMethod = "GET"
        req.timeoutInterval = 60 * 10
        req.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let (d, _) = try await send(req)
        let decoded = try JSONDecoder().decode(StatusResponse.self, from: d)
        if decoded.ok == false {
            throw APIError.serverMessage(decoded.error ?? "status failed")
        }
        return decoded
    }

    // MARK: 3️⃣ 다운로드
    func download(path: String) async throws -> Data {
        let clean = path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !clean.isEmpty else { throw APIError.serverMessage("대표 파일명이 비어 있습니다.") }

        var url = AppConfig.baseURL
        url.append(path: "download")
        url.append(path: clean)

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 60 * 10
        req.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, http) = try await send(req)

        if let ct = http.value(forHTTPHeaderField: "Content-Type"),
           !ct.lowercased().hasPrefix("image/") {
            let body = String(data: data, encoding: .utf8) ?? "<\(data.count) bytes>"
            throw APIError.serverMessage("이미지 응답이 아님 (Content-Type: \(ct))\n\(body)")
        }
        guard !data.isEmpty else { throw APIError.serverMessage("빈 바이트(0B) 수신") }
        return data
    }

    // MARK: 4️⃣ 유사도 분석 (RadarView 용)
    func analyze(jobId: String, filename: String? = nil) async throws -> AnalyzeResponse {
        var req = try makeRequest(path: "analyze", method: "POST", contentType: "application/json")
        var body: [String: Any] = ["jobId": jobId]
        if let filename { body["filename"] = filename }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (d, _) = try await send(req)
        let decoded = try JSONDecoder().decode(AnalyzeResponse.self, from: d)
        if decoded.ok == false {
            throw APIError.serverMessage(decoded.error ?? "analyze failed")
        }
        return decoded
    }

    // MARK: 5️⃣ 연습장 이미지
    func practice() async throws -> Data {
        let req = try makeRequest(path: "practice", method: "GET")
        let (d, _) = try await send(req)
        return d
    }
    func practice(jobId: String) async throws -> Data {
        let base = AppConfig.baseURL.appendingPathComponent("practice")
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "jobId", value: jobId)
        ]
        guard let url = comps.url else {
            throw APIError.invalidURL("practice url")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let (d, _) = try await send(req)
        return d
    }

    // MARK: 6️⃣ 연습 재검사 (/reanalyze)

    func reanalyze(practicePNG: Data, jobId: String) async throws -> ReanalyzeResponse {
        var req = URLRequest(url: AppConfig.baseURL.appendingPathComponent("reanalyze"))
        req.httpMethod = "POST"

        let boundary = "Inkly-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")   // ✅ 여기

        var body = Data()

        // ---- jobId ----
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"jobId\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(jobId)\r\n".data(using: .utf8)!)

        // ---- file ----
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"practice.png\"\r\n"
                .data(using: .utf8)!
        )
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(practicePNG)
        body.append("\r\n".data(using: .utf8)!)

        // ---- end ----
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        req.httpBody = body

        let (data, _) = try await session.data(for: req)
        let decoded = try JSONDecoder().decode(ReanalyzeResponse.self, from: data)

        if decoded.ok == false {
            throw APIError.serverMessage(decoded.error ?? "reanalyze failed")
        }
        return decoded
    }
}
extension APIClient {
    func handwritingCharURL(jobId: String, index: Int) -> URL {
        AppConfig.baseURL
            .appendingPathComponent("download")
            .appendingPathComponent("result\(jobId)")
            .appendingPathComponent("handwriting")
            .appendingPathComponent("\(index).png")
    }

    func generatedCharURL(jobId: String, index: Int) -> URL {
        AppConfig.baseURL
            .appendingPathComponent("download")
            .appendingPathComponent("result\(jobId)")
            .appendingPathComponent("generation")
            .appendingPathComponent("\(index).png")
    }
}

extension APIClient {
    func imageURL(path: String) -> URL? {
        AppConfig.baseURL.appendingPathComponent(path)
    }
}


