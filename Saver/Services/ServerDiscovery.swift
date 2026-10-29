import Foundation
import Network

// يبحث في شبكة الـ Wi-Fi عن خادم Saver (Bonjour) ويرجع عنوانه
// مثل ما يجد الآيفون الطابعات و Apple TV بدون كتابة IP
enum ServerDiscovery {
    // صندوق صغير يضمن أننا نُرجع النتيجة مرة واحدة فقط
    private final class Once {
        var done = false
    }

    static func find(timeout: TimeInterval = 3) async -> String? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "saver.discovery")
            let browser = NWBrowser(
                for: .bonjourWithTXTRecord(type: "_saver._tcp", domain: nil),
                using: .tcp
            )
            let once = Once()

            // كل الدوال تعمل على نفس الـ queue، فلا تتسابق
            func finish(_ address: String?) {
                guard !once.done else { return }
                once.done = true
                browser.cancel()
                continuation.resume(returning: address)
            }

            browser.browseResultsChangedHandler = { results, _ in
                for result in results {
                    // الخادم يضع عنوانه في TXT record باسم "url"
                    if case .bonjour(let txt) = result.metadata, let url = txt["url"] {
                        finish(url)
                        return
                    }
                }
            }
            browser.stateUpdateHandler = { state in
                if case .failed = state { finish(nil) }
            }
            browser.start(queue: queue)
            // إذا لم نجد شيئاً خلال المهلة نتوقف
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}
