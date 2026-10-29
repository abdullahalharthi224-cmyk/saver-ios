import SwiftUI

// الشاشة الرئيسية: حقل للرابط + زر تحميل (المرحلة 1)
struct ContentView: View {
    // @State: متغير تملكه الشاشة؛ أي تغيير فيه يعيد رسمها تلقائياً
    @State private var urlText = ""
    @State private var statusMessage: String?

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

                // زر لصق: لا يُظهر نافذة "Allow Paste" لأن المستخدم ضغطه بنفسه
                PasteButton(payloadType: String.self) { strings in
                    Task { @MainActor in
                        urlText = strings.first ?? ""
                    }
                }
                .buttonBorderShape(.capsule)

                // زر التحميل: معطّل إذا الحقل فارغ
                Button(action: startDownload) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedURL.isEmpty)

                // رسالة مؤقتة تؤكد الرابط (التحميل الحقيقي في المرحلة 2)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Saver")
        }
    }

    // ماذا يحدث عند الضغط على Download
    private func startDownload() {
        guard !trimmedURL.isEmpty else { return }
        statusMessage = "Got it: \(trimmedURL)"
    }
}

#Preview {
    ContentView()
}
