import SwiftUI

// شاشة الـ extension: تبدأ التحميل والحفظ تلقائياً عند فتحها
struct ShareView: View {
    let loadURL: () async -> URL?
    let close: () -> Void

    @State private var state: DownloadState = .idle
    @State private var url: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let url {
                    Text(url.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                statusView
                Spacer()
            }
            .padding()
            .navigationTitle("Saver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    // أثناء العمل الزر يلغي، وبعده يغلق
                    Button(state.isBusy ? "Cancel" : "Done", action: close)
                }
            }
        }
        .task { await run() }   // .task: يعمل مرة عند ظهور الشاشة
    }

    @ViewBuilder
    private var statusView: some View {
        switch state {
        case .idle, .resolving:
            ProgressView()
        case .downloading(let progress):
            if let progress {
                ProgressView(value: progress) {
                    Text("Downloading… \(Int(progress * 100))%")
                        .font(.footnote)
                        .monospacedDigit()
                }
            } else {
                ProgressView("Downloading…")
            }
        case .saving:
            ProgressView("Saving to Photos…")
        case .saved(let bytes):
            Label("Saved to Photos (\(bytes.formatted(.byteCount(style: .file))))",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .permissionDenied:
            Label("Open the Saver app and allow it to add videos to Photos.",
                  systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    // نفس خطوات التطبيق: تحقق ← تحميل ← حفظ
    private func run() async {
        guard let shared = await loadURL() else {
            state = .failed(message: "No link found in what you shared.")
            return
        }
        url = shared

        do {
            let validURL = try VideoDownloader.validatedURL(from: shared.absoluteString)
            state = .downloading(progress: nil)
            let fileURL = try await VideoDownloader().download(from: validURL) { progress in
                Task { @MainActor in
                    if case .downloading = state { state = .downloading(progress: progress) }
                }
            }
            let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? 0
            state = .saving
            try await PhotoLibrarySaver.saveVideo(at: fileURL)
            state = .saved(bytes: size)
        } catch SaveError.denied {
            state = .permissionDenied(fileURL: URL(fileURLWithPath: "/"))
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}
