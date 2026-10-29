import Foundation

// حالة الشاشة: قيمة واحدة فقط في كل لحظة
enum DownloadState: Equatable {
    case idle                                   // لا شيء يحدث
    case downloading(progress: Double?)         // nil = الحجم غير معروف بعد
    case finished(fileURL: URL, bytes: Int64)   // تم التحميل
    case failed(message: String)                // حدث خطأ

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }
}
