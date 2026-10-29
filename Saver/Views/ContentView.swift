import SwiftUI
import UIKit

// الشاشة الرئيسية: حقل للرابط + زر تحميل + شريط تقدم (المرحلة 5)
struct ContentView: View {
    // @State: متغير تملكه الشاشة؛ أي تغيير فيه يعيد رسمها تلقائياً
    @State private var urlText = ""
    @State private var state: DownloadState = .idle
    @Environment(\.openURL) private var openURL   // لفتح تطبيق الإعدادات
    // @AppStorage: مثل @State لكنه يُحفظ في الجهاز ويبقى بعد إغلاق التطبيق
    @AppStorage("serverAddress") private var serverAddress = ""
    @State private var showServerSettings = false

    // نحذف المسافات من البداية والنهاية قبل أي استخدام
    private var trimmedURL: String {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // حقل إدخال الرابط
                TextField("Paste a video link", text: $urlText)
                    .keyboardType(.URL)                  // كيبورد فيه / و .
                    .textInputAutocapitalization(.never) // لا تكبير للحروف
                    .autocorrectionDisabled()            // لا تصحيح تلقائي
                    .submitLabel(.go)
                    .onSubmit(startDownload)             // زر Go في الكيبورد
                    .padding(12)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                    .disabled(state.isBusy)

                // زر لصق: لا يُظهر نافذة "Allow Paste" لأن المستخدم ضغطه بنفسه
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in
                        urlText = strings.first ?? ""
                    }
                }
                .buttonBorderShape(.capsule)
                .disabled(state.isBusy)

                // زر التحميل: معطّل إذا الحقل فارغ أو التحميل جارٍ
                Button(action: startDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedURL.isEmpty || state.isBusy)

                statusView

                Spacer()
            }
            .padding()
            .navigationTitle("Saver")
            .toolbar {
                Button {
                    showServerSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Server Settings")
            }
            .sheet(isPresented: $showServerSettings) {
                ServerSettingsView(address: $serverAddress)
            }
        }
    }

    // ما يظهر تحت الزر حسب الحالة
    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .idle:
            EmptyView()
        case .resolving:
            ProgressView("Preparing video on your PC…")
        case .downloading(let progress):
            if let progress {
                ProgressView(value: progress) {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(.footnote)
                        .monospacedDigit()  // الأرقام بعرض ثابت فلا يهتز النص
                }
            } else {
                ProgressView("Downloading…") // دوّارة: الحجم غير معروف
            }
        case .saving:
            ProgressView("Saving to Photos…")
        case .saved(let bytes):
            Label("Saved to Photos (\(bytes.formatted(.byteCount(style: .file))))",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .permissionDenied(let fileURL):
            // الإذن مرفوض: نشرح ونعطي طريقاً للحل بدل رسالة خطأ فقط
            VStack(spacing: 10) {
                Label("Allow Saver to add videos: Settings → Saver → Photos → Add Photos Only.",
                      systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    Button("Try Saving Again") {
                        save(fileURL)
                    }
                }
                .buttonStyle(.bordered)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
    }

    // ماذا يحدث عند الضغط على Download
    private func startDownload() {
        guard !trimmedURL.isEmpty, !state.isBusy else { return }

        let url: URL
        do {
            url = try VideoDownloader.validatedURL(from: trimmedURL)
        } catch {
            state = .failed(message: error.localizedDescription)
            return
        }

        state = .downloading(progress: nil)
        // Task: نشغّل كود async من داخل زر (الزر نفسه ليس async)
        Task {
            do {
                let videoURL = try await resolveIfNeeded(url)
                state = .downloading(progress: nil)
                let fileURL = try await VideoDownloader().download(from: videoURL) { progress in
                    // التقدم يصل من خيط خلفي؛ تحديث الواجهة يجب أن يكون على الـ Main
                    Task { @MainActor in
                        if case .downloading = state { state = .downloading(progress: progress) }
                    }
                }
                save(fileURL)
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    // الخطوة الأولى: إذا كان الرابط صفحة (مثل TikTok) نطلب من الخادم تجهيز الفيديو
    private func resolveIfNeeded(_ url: URL) async throws -> URL {
        // رابط فيديو مباشر، أو لا يوجد خادم: نحمّل مباشرة كما في المرحلة 2
        if VideoDownloader.isDirectVideo(url) || serverAddress.isEmpty {
            return url
        }
        state = .resolving
        let client = try ResolverClient(address: serverAddress)
        return try await client.resolve(url).videoURL
    }

    // الخطوة الثالثة: حفظ الملف في الصور
    private func save(_ fileURL: URL) {
        // نقرأ الحجم قبل الحفظ لأن الملف يُحذف بعده
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
        state = .saving
        Task {
            do {
                try await PhotoLibrarySaver.saveVideo(at: fileURL)
                state = .saved(bytes: size)
            } catch SaveError.denied {
                state = .permissionDenied(fileURL: fileURL)
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }
}

#Preview {
    ContentView()
}
