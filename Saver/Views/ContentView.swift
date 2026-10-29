import SwiftUI

// الشاشة الرئيسية: حقل للرابط + زر تحميل + شريط تقدم (المرحلة 2)
struct ContentView: View {
    // @State: متغير تملكه الشاشة؛ أي تغيير فيه يعيد رسمها تلقائياً
    @State private var urlText = ""
    @State private var state: DownloadState = .idle

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
                    .disabled(state.isDownloading)

                // زر لصق: لا يُظهر نافذة "Allow Paste" لأن المستخدم ضغطه بنفسه
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in
                        urlText = strings.first ?? ""
                    }
                }
                .buttonBorderShape(.capsule)
                .disabled(state.isDownloading)

                // زر التحميل: معطّل إذا الحقل فارغ أو التحميل جارٍ
                Button(action: startDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedURL.isEmpty || state.isDownloading)

                statusView

                Spacer()
            }
            .padding()
            .navigationTitle("Saver")
        }
    }

    // ما يظهر تحت الزر حسب الحالة
    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .idle:
            EmptyView()
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
        case .finished(_, let bytes):
            Label("Downloaded \(bytes.formatted(.byteCount(style: .file)))",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
    }

    // ماذا يحدث عند الضغط على Download
    private func startDownload() {
        guard !trimmedURL.isEmpty, !state.isDownloading else { return }

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
                let fileURL = try await VideoDownloader().download(from: url) { progress in
                    // التقدم يصل من خيط خلفي؛ تحديث الواجهة يجب أن يكون على الـ Main
                    Task { @MainActor in
                        if state.isDownloading { state = .downloading(progress: progress) }
                    }
                }
                let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
                state = .finished(fileURL: fileURL, bytes: size)
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }
}

#Preview {
    ContentView()
}
