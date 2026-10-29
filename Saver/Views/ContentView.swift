import SwiftUI

// الشاشة الأولى: مجرد نص للتأكد أن التطبيق يعمل (المرحلة 0)
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Saver")
                .font(.largeTitle.bold())
            Text("Phase 0 works ✅")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
