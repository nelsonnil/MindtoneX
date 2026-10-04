import Foundation

/// Lightweight OpenAI check before AI Voice Perform (avoid arming mid-trick on bad key or quota).
enum VoiceOpenAIPreflight {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// `nil` = OK; non-nil = user-facing English message (stay on home screen).
    static func checkBeforePerform() async -> String? {
        guard let key = VoiceSettings.apiKey else {
            return "Add your OpenAI API key under Voice → Connection before performing."
        }
        return await validate(apiKey: key)
    }

    static func validate(apiKey: String) async -> String? {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models?limit=1")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 {
                dlog("[VOICE] OpenAI preflight OK (HTTP 200)")
                return nil
            }
            let body = String(decoding: data, as: UTF8.self)
            let message = friendlyMessage(httpStatus: status, body: body)
            dlog("✗ [VOICE] OpenAI preflight failed: HTTP \(status) · \(body.prefix(280))")
            return message
        } catch {
            let message = friendlyMessage(error: error)
            dlog("✗ [VOICE] OpenAI preflight network: \(error.localizedDescription)")
            return message
        }
    }

    private static func friendlyMessage(httpStatus: Int, body: String) -> String {
        let parsed = parseOpenAIErrorBody(body)
        if parsed.code == "insufficient_quota" || parsed.type == "insufficient_quota" {
            return "OpenAI account has no remaining balance or quota. Add credits in your OpenAI billing settings, then try Perform again."
        }
        switch httpStatus {
        case 401:
            return "OpenAI API key is invalid or revoked. Update it under Voice → Connection."
        case 403:
            return "OpenAI rejected this API key (access denied). Check the key and your OpenAI project permissions."
        case 429:
            if parsed.message.lowercased().contains("quota") || parsed.message.lowercased().contains("billing") {
                return "OpenAI quota or billing limit reached. Check your account balance, then try Perform again."
            }
            return "OpenAI rate limit hit. Wait a moment and try Perform again."
        case 500...599:
            return "OpenAI is temporarily unavailable (HTTP \(httpStatus)). Try Perform again in a minute."
        default:
            if !parsed.message.isEmpty { return parsed.message }
            return "OpenAI connection failed (HTTP \(httpStatus)). Check your key and network, then try again."
        }
    }

    private static func friendlyMessage(error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No internet connection. Connect to Wi‑Fi or cellular data, then try Perform again."
            case .timedOut:
                return "OpenAI connection timed out. Check your network and try Perform again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Can't reach OpenAI. Check your network or VPN, then try Perform again."
            default:
                break
            }
        }
        return "Couldn't reach OpenAI (\(error.localizedDescription)). Check your network and API key."
    }

    private static func parseOpenAIErrorBody(_ body: String) -> (message: String, type: String, code: String) {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let err = json["error"] as? [String: Any] else {
            return ("", "", "")
        }
        let message = err["message"] as? String ?? ""
        let type = err["type"] as? String ?? ""
        let code = err["code"] as? String ?? ""
        return (message, type, code)
    }
}
