import UIKit
import SwiftUI
import UniformTypeIdentifiers

// iOS يبدأ الـ extension من هذا الكلاس (اسمه مكتوب في Info.plist)
// @objc(...) يثبّت الاسم حتى يجده iOS بدون اسم الـ module
@objc(ShareViewController)
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let shareView = ShareView(
            loadURL: { [weak self] in await self?.sharedURL() },
            close: { [weak self] in
                // نخبر iOS أننا انتهينا فيغلق الشاشة
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )

        // UIHostingController: جسر يضع شاشة SwiftUI داخل UIKit
        let host = UIHostingController(rootView: shareView)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    // نبحث في المحتوى المُشارك عن رابط (كـ URL أو داخل نص)
    private func sharedURL() async -> URL? {
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return url
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = Self.firstURL(in: text) {
                return url
            }
        }
        return nil
    }

    // NSDataDetector: أداة من Apple تجد الروابط داخل أي نص
    private static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }
}
