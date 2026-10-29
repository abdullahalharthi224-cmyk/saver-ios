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
                    Text("Start run.bat on your PC and type the address it shows. Leave empty to use direct video links only.")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(address.isEmpty || isTesting)

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
            let version = try await ResolverClient(address: address).health()
            testResult = "✅ Connected (yt-dlp \(version))"
        } catch {
            testResult = "❌ \(error.localizedDescription)"
        }
    }
}
