import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// シェアシートのエントリポイント。共有された URL を抽出して ShareStockView を表示する。
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await presentShareView() }
    }

    private func presentShareView() async {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let url = await extractSharedURL(from: item) else {
            close()
            return
        }
        let title = Self.extractSharedTitle(from: item)
        let hosting = UIHostingController(rootView: ShareStockView(url: url, title: title, onFinish: { [weak self] in self?.close() }))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func extractSharedURL(from item: NSExtensionItem) async -> URL? {
        guard let provider = item.attachments?.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 共有元(Safari 等)が付与するページタイトルを取得する。
    /// 拡張プロセスはメモリ制限が厳しいため、WebKit やネットワーク取得は行わず、
    /// 共有シートが既に渡している attributedContentText のみを使う。
    private static func extractSharedTitle(from item: NSExtensionItem) -> String? {
        let title = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return (title?.isEmpty ?? true) ? nil : title
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
