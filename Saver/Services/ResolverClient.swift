import Foundation

enum ResolverError: LocalizedError {
    case badAddress
    case unreachable
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badAddress:
            return "Server address is not valid. Example: http://192.168.1.10:8000"
        case .unreachable:
            return "Can't reach your PC. Make sure run.bat is running and the iPhone is on the same Wi-Fi."
        case .server(let message):
            return "Server: \(message)"
        }
    }
}

// يتكلم مع الخادم على جهازك (backend/main.py)
struct ResolverClient {
    let baseURL: URL

    // أخطاء تعني "الجهاز غير متاح" وليس "الرابط خطأ"
    private static let unreachableCodes: [URLError.Code] = [
        .cannotConnectToHost, .cannotFindHost, .timedOut,
        .networkConnectionLost, .notConnectedToInternet,
    ]

    // نقبل "192.168.1.10:8000" ونضيف http:// تلقائياً
    init(address: String) throws {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.lowercased().hasPrefix("http") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), url.host != nil else { throw ResolverError.badAddress }
        baseURL = url
    }

    // شكل ردود الخادم (نفس أسماء الحقول في JSON)
    private struct ResolveResponse: Decodable { let video_url: String; let title: String }
    private struct HealthResponse: Decodable { let yt_dlp: String }
    private struct ErrorResponse: Decodable { let detail: String }

    // POST /resolve {url} → رابط فيديو على جهازك
    func resolve(_ pageURL: URL) async throws -> (videoURL: URL, title: String) {
        var request = URLRequest(url: baseURL.appendingPathComponent("resolve"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["url": pageURL.absoluteString])
        request.timeoutInterval = 180  // yt-dlp يحمّل الفيديو أولاً، فقد يأخذ وقتاً

        let result: ResolveResponse = try await send(request)
        guard let videoURL = URL(string: result.video_url) else {
            throw ResolverError.server("Invalid video link from server.")
        }
        return (videoURL, result.title)
    }

    // GET /health → رقم إصدار yt-dlp (لزر Test Connection)
    func health() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 10
        let result: HealthResponse = try await send(request)
        return result.yt_dlp
    }

    // دالة عامة: ترسل الطلب وتحوّل JSON إلى struct (Generic <T>)
    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch let error as URLError where Self.unreachableCodes.contains(error.code) {
            throw ResolverError.unreachable
        }
        let (data, response) = result

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // FastAPI يرسل سبب الخطأ في {"detail": "..."}
            let detail = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.detail
            throw ResolverError.server(detail ?? "HTTP \(status)")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
