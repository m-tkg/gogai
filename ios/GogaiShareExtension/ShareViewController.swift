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
        guard let url = await extractSharedURL() else {
            close()
            return
        }
        let hosting = UIHostingController(rootView: ShareStockView(url: url, onFinish: { [weak self] in self?.close() }))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func extractSharedURL() async -> URL? {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: {
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

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
