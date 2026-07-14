import Foundation
import FoundationModels

/// AI 機能の入口。
/// ユーザー方針により iOS/iPadOS 27 以上でのみ機能を有効化する
/// （API 自体は iOS 26 から存在するが、プロバイダー差し替え可能な
///  LanguageModel プロトコル世代である 27 をオンデバイスの最低ラインとする）。
enum LocalAI {
    /// 設定済みの外部 AI、またはオンデバイスモデルが利用可能なとき true
    static var isAvailable: Bool {
        resolvedProvider() != nil
    }

    static var activeProviderLabel: String {
        resolvedProvider()?.label ?? AIProvider.current.label
    }

    static var cacheIdentifier: String {
        resolvedProvider()?.rawValue ?? AIProvider.current.rawValue
    }

    private static var isOnDeviceAvailable: Bool {
        guard #available(iOS 27.0, *) else { return false }
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    /// ローカル AI が使えない理由。使える場合は nil。
    static var unavailableReason: String? {
        if isAvailable { return nil }
        switch AIProvider.current {
        case .openAI, .gemini, .claude:
            return "\(AIProvider.current.label) の API キーが設定されていません。設定画面で API キーを入力してください。"
        case .automatic:
            return "外部 AI の API キーが未設定で、オンデバイス基盤モデルも利用できません。設定画面で OpenAI/Gemini/Claude の API キーを入力するか、iOS/iPadOS 27 以上でオンデバイス基盤モデルを有効にしてください。"
        case .onDevice:
            return onDeviceUnavailableReason
        }
    }

    private static var onDeviceUnavailableReason: String {
        guard #available(iOS 27.0, *) else {
            return "要約には iOS/iPadOS 27 以上とオンデバイス基盤モデルが必要です。"
        }
        return "オンデバイス基盤モデルが利用できません: \(SystemLanguageModel.default.availability)"
    }

    /// 利用可能なら既定のオンデバイス実装で LocalArticleAI を作る
    static func makeArticleAI() -> LocalArticleAI? {
        guard let generator = makeGenerator() else { return nil }
        return LocalArticleAI(generator: generator)
    }

    /// 利用可能なら既定のオンデバイス TextGenerating 実装を返す(ストック要約など LocalArticleAI 以外の用途で共用)
    static func makeGenerator() -> (any TextGenerating)? {
        guard let provider = resolvedProvider() else { return nil }
        switch provider {
        case .openAI, .gemini, .claude:
            guard let apiKey = provider.apiKey else { return nil }
            return RemoteAITextGenerator(provider: provider, apiKey: apiKey)
        case .onDevice:
            guard #available(iOS 27.0, *), isOnDeviceAvailable else { return nil }
            return FoundationModelTextGenerator()
        case .automatic:
            return nil
        }
    }

    private static func resolvedProvider() -> AIProvider? {
        switch AIProvider.current {
        case .automatic:
            if AIProvider.openAI.apiKey != nil { return .openAI }
            if AIProvider.gemini.apiKey != nil { return .gemini }
            if AIProvider.claude.apiKey != nil { return .claude }
            return isOnDeviceAvailable ? .onDevice : nil
        case .openAI, .gemini, .claude:
            return AIProvider.current.apiKey == nil ? nil : AIProvider.current
        case .onDevice:
            return isOnDeviceAvailable ? .onDevice : nil
        }
    }
}

/// OpenAI / Gemini / Claude のテキスト生成 API を TextGenerating に揃える実装。
struct RemoteAITextGenerator: TextGenerating {
    private let provider: AIProvider
    private let apiKey: String
    private let session: URLSession

    init(provider: AIProvider, apiKey: String, session: URLSession = .shared) {
        self.provider = provider
        self.apiKey = apiKey
        self.session = session
    }

    func generate(instructions: String, prompt: String) async throws -> String {
        switch provider {
        case .openAI:
            return try await generateOpenAI(instructions: instructions, prompt: prompt)
        case .gemini:
            return try await generateGemini(instructions: instructions, prompt: prompt)
        case .claude:
            return try await generateClaude(instructions: instructions, prompt: prompt)
        case .automatic, .onDevice:
            throw LocalAIError.aiUnavailable
        }
    }

    private func generateOpenAI(instructions: String, prompt: String) async throws -> String {
        struct Body: Encodable {
            let model: String
            let instructions: String
            let input: String
        }
        let data = try await postJSON(
            url: URL(string: "https://api.openai.com/v1/responses")!,
            headers: ["Authorization": "Bearer \(apiKey)"],
            body: Body(model: "gpt-5.5", instructions: instructions, input: prompt)
        )
        struct Response: Decodable {
            struct Output: Decodable {
                struct Content: Decodable {
                    let type: String?
                    let text: String?
                }
                let content: [Content]?
            }
            let output_text: String?
            let output: [Output]?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let text = response.output_text, !text.isEmpty { return text }
        let text = response.output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""
        guard !text.isEmpty else { throw LocalAIError.parseFailed }
        return text
    }

    private func generateGemini(instructions: String, prompt: String) async throws -> String {
        struct Body: Encodable {
            struct Content: Encodable {
                struct Part: Encodable {
                    let text: String
                }
                let role: String?
                let parts: [Part]
            }
            let systemInstruction: Content
            let contents: [Content]
        }
        let data = try await postJSON(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")!,
            headers: ["x-goog-api-key": apiKey],
            body: Body(
                systemInstruction: .init(role: nil, parts: [.init(text: instructions)]),
                contents: [.init(role: "user", parts: [.init(text: prompt)])]
            )
        )
        struct Response: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable {
                        let text: String?
                    }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let output_text: String?
            let candidates: [Candidate]?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        if let text = response.output_text, !text.isEmpty { return text }
        let text = response.candidates?
            .compactMap(\.content)
            .flatMap { $0.parts ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""
        guard !text.isEmpty else { throw LocalAIError.parseFailed }
        return text
    }

    private func generateClaude(instructions: String, prompt: String) async throws -> String {
        struct Body: Encodable {
            struct Message: Encodable {
                let role: String
                let content: String
            }
            let model: String
            let max_tokens: Int
            let system: String
            let messages: [Message]
        }
        let body = Body(
            model: "claude-sonnet-4-5",
            max_tokens: 4096,
            system: instructions,
            messages: [.init(role: "user", content: prompt)]
        )
        let data = try await postJSON(
            url: URL(string: "https://api.anthropic.com/v1/messages")!,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
            ],
            body: body
        )
        struct Response: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }
            let content: [Content]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let text = response.content.compactMap(\.text).joined(separator: "\n")
        guard !text.isEmpty else { throw LocalAIError.parseFailed }
        return text
    }

    private func postJSON<Body: Encodable>(url: URL, headers: [String: String], body: Body) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Apple のオンデバイス基盤モデル（Foundation Models framework）による実装
@available(iOS 26.0, *)
struct FoundationModelTextGenerator: TextGenerating {
    /// contextSizeExceeded を受けてプロンプトを縮小し再試行する最大回数
    static let maxContextRetries = 2
    /// concurrentRequests を受けて短い待機の後に再試行する最大回数
    static let maxConcurrentRetries = 2
    /// concurrentRequests 検知時の待機時間(要約キューが翻訳優先で中断した際、
    /// オンデバイスモデル側の処理がまだ終わっていない場合の猶予)
    static let concurrentRetryDelay: Duration = .milliseconds(300)
    /// rateLimited を受けて再試行する最大回数
    static let maxRateLimitRetries = 2
    /// rateLimited 検知時の待機時間(試行ごとに指数的に伸ばす)
    static let rateLimitRetryDelays: [Duration] = [.seconds(1), .seconds(2)]

    func generate(instructions: String, prompt: String) async throws -> String {
        try await generate(
            instructions: instructions, prompt: prompt,
            remainingContextRetries: Self.maxContextRetries,
            remainingConcurrentRetries: Self.maxConcurrentRetries,
            remainingRateLimitRetries: Self.maxRateLimitRetries
        )
    }

    private func generate(
        instructions: String, prompt: String,
        remainingContextRetries: Int, remainingConcurrentRetries: Int, remainingRateLimitRetries: Int
    ) async throws -> String {
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: prompt)
            return response.content
        } catch {
            if remainingConcurrentRetries > 0, Self.isConcurrentRequestsError(error) {
                try await Task.sleep(for: Self.concurrentRetryDelay)
                return try await generate(
                    instructions: instructions, prompt: prompt,
                    remainingContextRetries: remainingContextRetries,
                    remainingConcurrentRetries: remainingConcurrentRetries - 1,
                    remainingRateLimitRetries: remainingRateLimitRetries
                )
            }
            if remainingRateLimitRetries > 0, Self.isRateLimitedError(error) {
                let attempt = Self.maxRateLimitRetries - remainingRateLimitRetries
                try await Task.sleep(for: Self.rateLimitRetryDelays[attempt])
                return try await generate(
                    instructions: instructions, prompt: prompt,
                    remainingContextRetries: remainingContextRetries,
                    remainingConcurrentRetries: remainingConcurrentRetries,
                    remainingRateLimitRetries: remainingRateLimitRetries - 1
                )
            }
            guard remainingContextRetries > 0, let shrunkPrompt = Self.shrinkPromptIfContextExceeded(prompt, error: error) else {
                throw error
            }
            return try await generate(
                instructions: instructions, prompt: shrunkPrompt,
                remainingContextRetries: remainingContextRetries - 1,
                remainingConcurrentRetries: remainingConcurrentRetries,
                remainingRateLimitRetries: remainingRateLimitRetries
            )
        }
    }

    /// LanguageModelSession.Error.concurrentRequests(オンデバイスモデルは同時に1リクエストしか
    /// 処理できない)を検知する。型ではなくキーワードで判定する理由は shrinkPromptIfContextExceeded と同じ。
    static func isConcurrentRequestsError(_ error: Error) -> Bool {
        String(describing: error).lowercased().contains("concurrentrequests")
    }

    /// LanguageModelSession.Error.rateLimited / LanguageModelError.rateLimited(オンデバイスモデルの
    /// 単位時間あたりのリクエスト数制限)を検知する。型ではなくキーワードで判定する理由は
    /// shrinkPromptIfContextExceeded と同じ。
    static func isRateLimitedError(_ error: Error) -> Bool {
        String(describing: error).lowercased().contains("ratelimited")
    }

    /// コンテキスト長超過エラーを受けてプロンプトを縮める。
    /// 対応するエラー型(LanguageModelError.contextSizeExceeded 等)はビルドに使う
    /// Xcode/SDK バージョンによって存在しないことがある(型で判定すると環境依存でビルドが壊れる)ため、
    /// エラーの説明文言に含まれるキーワードで判定する。
    /// それ以外のエラーや、これ以上縮められない場合は nil を返す(= リトライしない)。
    static func shrinkPromptIfContextExceeded(_ prompt: String, error: Error) -> String? {
        let description = String(describing: error).lowercased()
        guard description.contains("context"),
              description.contains("exceed") || description.contains("window") else {
            return nil
        }
        let targetLength = max(200, prompt.count / 2)
        guard targetLength < prompt.count else { return nil }
        return String(prompt.prefix(targetLength))
    }
}
