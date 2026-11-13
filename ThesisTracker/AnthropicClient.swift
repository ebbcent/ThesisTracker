import Foundation

// MARK: - 5.13 Professeur : appel à l'API Messages d'Anthropic
//
// Pas de dépendance externe : une requête JSON par échange. Les consignes et
// le contexte du coffre sont marqués pour le cache de requêtes (prompt
// caching) : à partir du deuxième échange d'une séance, ils sont relus depuis
// le cache, ce qui réduit le coût.

struct AnthropicClient {
    struct Message: Equatable {
        enum Role: String { case user, assistant }
        let role: Role
        let text: String
        /// Texte joint (dépôt à relire), envoyé avant le message et mis en cache.
        var attachment: String? = nil
    }

    struct Usage: Equatable {
        var input = 0
        var cacheRead = 0
        var cacheWrite = 0
        var output = 0
    }

    struct Reply: Equatable {
        let text: String
        let usage: Usage
        let stoppedAtLimit: Bool
    }

    enum ClientError: LocalizedError {
        case noKey
        case http(Int, String)
        case empty
        var errorDescription: String? {
            switch self {
            case .noKey: return "Ajoute d'abord ta clé API dans Réglages › Professeur."
            case .http(let code, let message):
                switch code {
                case 401: return "Clé API refusée (401). Vérifie-la dans Réglages › Professeur."
                case 429: return "Trop de requêtes ou crédit épuisé (429). \(message)"
                case 529, 503: return "Le service est surchargé (\(code)). Réessaie dans un instant."
                default: return "L'API a répondu avec le code \(code). \(message)"
                }
            case .empty: return "Réponse vide."
            }
        }
    }

    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let apiVersion = "2023-06-01"

    let apiKey: String
    let model: String
    var maxTokens = 4096

    /// Corps JSON de la requête (séparé pour les tests).
    static func requestBody(model: String, maxTokens: Int, persona: String, context: String, messages: [Message]) -> [String: Any] {
        let system: [[String: Any]] = [
            ["type": "text", "text": persona],
            ["type": "text", "text": context, "cache_control": ["type": "ephemeral"]]
        ]
        let apiMessages: [[String: Any]] = messages.map { message in
            var blocks: [[String: Any]] = []
            if let attachment = message.attachment {
                blocks.append(["type": "text", "text": attachment, "cache_control": ["type": "ephemeral"]])
            }
            blocks.append(["type": "text", "text": message.text])
            return ["role": message.role.rawValue, "content": blocks]
        }
        return [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": apiMessages
        ]
    }

    static func parseReply(_ data: Data) throws -> Reply {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ClientError.empty }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw ClientError.empty }
        let u = json["usage"] as? [String: Any] ?? [:]
        let usage = Usage(input: u["input_tokens"] as? Int ?? 0,
                          cacheRead: u["cache_read_input_tokens"] as? Int ?? 0,
                          cacheWrite: u["cache_creation_input_tokens"] as? Int ?? 0,
                          output: u["output_tokens"] as? Int ?? 0)
        return Reply(text: text, usage: usage, stoppedAtLimit: (json["stop_reason"] as? String) == "max_tokens")
    }

    func send(persona: String, context: String, messages: [Message]) async throws -> Reply {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body = Self.requestBody(model: model, maxTokens: maxTokens, persona: persona, context: context, messages: messages)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var message = ""
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any] {
                message = error["message"] as? String ?? ""
            }
            throw ClientError.http(status, message)
        }
        return try Self.parseReply(data)
    }
}
