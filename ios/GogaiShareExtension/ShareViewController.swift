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
        let title = await resolveTitle(from: item, url: url)
        let hosting = UIHostingController(rootView: ShareStockView(url: url, title: title, onFinish: { [weak self] in self?.close() }))
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    /// ページタイトルを複数の経路で順に試す。
    /// 共有元アプリ(Safari/Chrome/他)によってどの経路が使えるかが異なるため、
    /// メタデータベースの手段を優先し、どれも失敗した場合のみネットワーク取得にフォールバックする。
    private func resolveTitle(from item: NSExtensionItem, url: URL) async -> String? {
        if let title = await extractJavaScriptPreprocessingTitle(from: item) {
            return title
        }
        if let title = Self.extractAttributedTitle(from: item) {
            return title
        }
        if let title = await extractPlainTextAttachmentTitle(from: item) {
            return title
        }
        return await Self.fetchPageTitle(from: url)
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
    /// この仕組みは Safari 自身が実行するものであり、Chrome 等の他ブラウザから共有された
    /// 場合はこの添付が無いため nil を返す。
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

    /// 共有元アプリが NSExtensionItem 自体に付与するタイトルを取得する(Chrome 等の一部アプリが利用)。
    private static func extractAttributedTitle(from item: NSExtensionItem) -> String? {
        normalizeTitle(item.attributedTitle?.string) ?? normalizeTitle(item.attributedContentText?.string)
    }

    /// URL 添付とは別にプレーンテキストの添付(タイトルなど)がある場合にそれを使う。
    private func extractPlainTextAttachmentTitle(from item: NSExtensionItem) async -> String? {
        guard let provider = item.attachments?.first(where: { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
                && !provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        }) else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                let title = Self.normalizeTitle(item as? String)
                continuation.resume(returning: title)
            }
        }
    }

    /// URL から HTML を軽量に取得し `<title>` タグを抽出する(共有元のメタデータが一切取れない場合の最終手段)。
    /// 拡張プロセスのメモリ制限を考慮し、先頭 64KB のみを読んで打ち切る(WebKit は使わない)。
    private static func fetchPageTitle(from url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (byteStream, response) = try? await URLSession.shared.bytes(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        var data = Data()
        data.reserveCapacity(65536)
        do {
            for try await byte in byteStream {
                data.append(byte)
                if data.count >= 65536 { break }
            }
        } catch {
            // 途中まで読めていればそのデータで抽出を試みる
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        return extractTitleTag(from: html)
    }

    private static func extractTitleTag(from html: String) -> String? {
        guard let range = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let inner = String(html[range])
            .replacingOccurrences(of: "<title[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</title>", with: "", options: [.caseInsensitive])
        return normalizeTitle(decodeHTMLEntities(inner))
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "),
        ]
        return entities.reduce(text) { result, entity in
            result.replacingOccurrences(of: entity.0, with: entity.1)
        }
    }

    private static nonisolated func normalizeTitle(_ title: String?) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    private func close() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
