import Foundation
import Photos

enum SaveError: LocalizedError {
    case denied
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Saver is not allowed to add videos to Photos."
        case .failed(let message):
            return "Could not save to Photos: \(message)"
        }
    }
}

// يحفظ ملف فيديو في تطبيق الصور
enum PhotoLibrarySaver {
    static func saveVideo(at fileURL: URL) async throws {
        // addOnly: إذن إضافة فقط، التطبيق لا يرى صورك
        // أول مرة تظهر نافذة السؤال، وبعدها يُرجع iOS الجواب المحفوظ مباشرة
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized else { throw SaveError.denied }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }
        } catch {
            // غالباً: صيغة فيديو لا يدعمها iOS
            throw SaveError.failed(error.localizedDescription)
        }

        // الصور أخذت نسخة، فنحذف ملفنا المؤقت لتوفير المساحة
        try? FileManager.default.removeItem(at: fileURL)
    }
}
