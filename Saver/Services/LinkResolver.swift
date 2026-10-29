import Foundation

// يقرر: نحمّل الرابط مباشرة، أم نطلب من الخادم على جهازك تجهيزه؟
// @MainActor: لأن onResolving يغيّر الواجهة
@MainActor
enum LinkResolver {
    static func videoURL(for url: URL, manualAddress: String,
                         onResolving: () -> Void) async throws -> URL {
        // رابط فيديو مباشر: لا نحتاج الخادم
        if VideoDownloader.isDirectVideo(url) { return url }

        onResolving()
        // نبحث عن الخادم تلقائياً أولاً، ثم العنوان المكتوب يدوياً (إن وُجد)
        let found = await ServerDiscovery.find()
        let address = found ?? (manualAddress.isEmpty ? nil : manualAddress)

        // لا يوجد خادم: نجرّب مباشرة (وإن كانت صفحة سيظهر خطأ "not a video")
        guard let address else { return url }
        return try await ResolverClient(address: address).resolve(url).videoURL
    }
}
