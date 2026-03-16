import Foundation

@MainActor
final class ServerURLManager: ObservableObject {
    private let userDefaultsKey = "serverURL"

    @Published private(set) var serverURL: URL?

    var isConfigured: Bool { serverURL != nil }

    init() {
        if let urlString = UserDefaults.standard.string(forKey: userDefaultsKey),
           let url = URL(string: urlString) {
            serverURL = url
        }
    }

    func setServerURL(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: userDefaultsKey)
        serverURL = url
    }

    func clearServerURL() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        serverURL = nil
    }
}
