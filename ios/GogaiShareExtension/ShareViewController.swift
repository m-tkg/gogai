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
        let title = await extractJavaScriptPreprocessingTitle(from: item) ?? Self.extractSharedTitle(from: item)
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

    /// Safari が `NSExtensionJavaScriptPreprocessingFile`(ShareExtensionPreprocessor.js)経由で
    /// 渡すページ情報(document.title 等)を取得する。WebKit を拡張プロセス内で動かさずに済む
    /// Apple 標準の仕組み(iOS 8 以降のアクション拡張向け JS プリプロセッシング)。
    /// Safari 以外から共有された場合はこの添付が無いため nil を返す。
    private func extractJavaScriptPreprocessingTitle(from item: NSExtensionItem) async -> String? {
        guard let provider = item.attachments?.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier)
        }) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier, options: nil) { item, _ in
                let dict = item as? [String: Any]
                let results = dict?[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any]
                let title = Self.normalizeTitle(results?["title"] as? String)
                continuation.resume(returning: title)
            }
        }
    }

    /// 共有元が付与するページタイトルを取得する(JS プリプロセッシングが使えない場合のフォールバック)。
    /// 拡張プロセスはメモリ制限が厳しいため、WebKit やネットワーク取得は行わず、
    /// 共有シートが既に渡している attributedContentText のみを使う。
    private static func extractSharedTitle(from item: NSExtensionItem) -> String? {
        normalizeTitle(item.attributedContentText?.string)
    }

    private static nonisolated func normalizeTitle(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
