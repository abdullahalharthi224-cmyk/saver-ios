import Foundation

// حالة الشاشة: قيمة واحدة فقط في كل لحظة
enum DownloadState: Equatable {
    case idle                                   // لا شيء يحدث
    case downloading(progress: Double?)         // nil = الحجم غير معروف بعد
    case saving                                 // نحفظ في الصور
    case saved(bytes: Int64)                    // تم الحفظ في الصور
    case permissionDenied(fileURL: URL)         // الملف جاهز لكن لا يوجد إذن
    case failed(message: String)                // حدث خطأ

    // هل هناك عمل جارٍ؟ (نعطّل الأزرار وقتها)
    var isBusy: Bool {
        switch self {
        case .downloading, .saving: return true
        default: return false
        }
    }
}
