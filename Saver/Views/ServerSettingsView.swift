import SwiftUI

// شاشة ⚙️: عنوان الخادم على جهازك + اختبار الاتصال
struct ServerSettingsView: View {
    @Binding var address: String
    @Environment(\.dismiss) private var dismiss
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("http://192.168.1.10:8000", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("PC Server Address")
                } footer: {
                    Text("Leave empty: Saver finds your PC by itself. Type an address only if automatic search fails.")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text(address.isEmpty ? "Search for My PC" : "Test Connection")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult).font(.footnote)
                    }
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }   // defer: يُنفّذ عند الخروج من الدالة مهما حدث
        do {
            // بدون عنوان: نبحث تلقائياً كما يفعل التطبيق عند التحميل
            var target = address
            if target.isEmpty {
                guard let found = await ServerDiscovery.find() else {
                    testResult = "❌ No PC found. Is SaverServer running on the same Wi-Fi?"
                    return
                }
                target = found
            }
            let version = try await ResolverClient(address: target).health()
            testResult = "✅ Connected to \(target) (yt-dlp \(version))"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}
