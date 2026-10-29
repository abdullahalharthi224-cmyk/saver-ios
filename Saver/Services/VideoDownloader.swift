import Foundation

// أنواع الأخطاء مع رسالة واضحة لكل واحد
enum DownloadError: LocalizedError {
    case invalidURL
    case noInternet
    case notAVideo(contentType: String?)
    case badStatus(Int)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "This link is not valid. It must start with http:// or https://"
        case .noInternet:
            return "No internet connection. Check Wi-Fi or cellular data."
        case .notAVideo(let type):
            return "This link is not a video file (type: \(type ?? "unknown"))."
        case .badStatus(let code):
            return "The server refused the download (HTTP \(code))."
        case .other(let message):
            return message
        }
    }
}

// يحمّل ملفاً ويبلّغ عن نسبة التقدم
// نستخدم delegate لأن هذه الطريقة هي التي تعطينا didWriteData (التقدم)
final class VideoDownloader: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private var onProgress: ((Double) -> Void)?
    private var lastReported = -1.0
    private var resultURL: URL?
    private var resultError: Error?

    // التحقق من الرابط قبل البدء
    static func validatedURL(from text: String) throws -> URL {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw DownloadError.invalidURL
        }
        return url
    }

    // يبدأ التحميل وينتظر حتى ينتهي، ثم يرجع مكان الملف على الجهاز
    func download(from url: URL, onProgress: @escaping (Double) -> Void) async throws -> URL {
        self.onProgress = onProgress
        // جلسة جديدة لكل تحميل؛ نغلقها في النهاية حتى لا تبقى في الذاكرة
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    // يُستدعى كثيراً أثناء التحميل
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return } // الخادم لم يرسل الحجم
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        // نبلّغ فقط كل 1% حتى لا نرهق الواجهة
        if progress - lastReported >= 0.01 || progress >= 1 {
            lastReported = progress
            onProgress?(progress)
        }
    }

    // انتهى التحميل: الملف مؤقت ويُحذف بعد هذه الدالة، لذلك ننقله فوراً
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let response = downloadTask.response as? HTTPURLResponse
        if let status = response?.statusCode, !(200..<300).contains(status) {
            resultError = DownloadError.badStatus(status)
            return
        }

        // هل هو فيديو؟ نقبل video/* أو امتداد فيديو معروف
        let videoExtensions = ["mp4", "mov", "m4v"]
        let mime = response?.mimeType?.lowercased()
        let name = response?.suggestedFilename ?? "video.mp4"
        let ext = (name as NSString).pathExtension.lowercased()
        guard mime?.hasPrefix("video/") == true || videoExtensions.contains(ext) else {
            resultError = DownloadError.notAVideo(contentType: mime)
            return
        }

        // ننقل الملف إلى tmp باسم فريد وامتداد صحيح (Photos يحتاج الامتداد)
        let fileName = UUID().uuidString + "." + (videoExtensions.contains(ext) ? ext : "mp4")
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            resultURL = destination
        } catch {
            resultError = DownloadError.other("Could not save the file: \(error.localizedDescription)")
        }
    }

    // آخر دالة تُستدعى دائماً (نجاح أو فشل): هنا نُرجع النتيجة مرة واحدة فقط
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                resultError = DownloadError.noInternet
            default:
                resultError = DownloadError.other(urlError.localizedDescription)
            }
        } else if let error {
            resultError = DownloadError.other(error.localizedDescription)
        }

        if let resultURL, resultError == nil {
            continuation?.resume(returning: resultURL)
        } else {
            continuation?.resume(throwing: resultError ?? DownloadError.other("Unknown error"))
        }
        continuation = nil
    }
}
