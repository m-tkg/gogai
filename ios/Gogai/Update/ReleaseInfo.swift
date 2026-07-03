import Foundation

struct ReleaseInfo: Decodable, Equatable, Sendable {
    let tagName: String
    let htmlUrl: String
    let assets: [Asset]

    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadUrl: String

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadUrl = "browser_download_url"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case assets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlUrl = try container.decode(String.self, forKey: .htmlUrl)
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    var zipAssetURL: URL? {
        assets.first { $0.name.hasSuffix(".zip") }
            .flatMap { URL(string: $0.browserDownloadUrl) }
    }
}

enum VersionComparator {
    static func isNewer(tag: String, than current: String) -> Bool {
        let a = components(tag)
        let b = components(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        let trimmed = (version.hasPrefix("v") || version.hasPrefix("V"))
            ? String(version.dropFirst()) : version
        return trimmed.split(separator: ".").map { part in
            Int(part.prefix { $0.isNumber }) ?? 0
        }
    }
}
