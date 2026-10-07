import Foundation

/// Lightweight speech-service check before AI Voice Perform (avoid arming mid-trick on bad key or quota).
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
            return "Add your OpenAI API key under Home → Performance settings before performing."
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

    /// Strips vendor/model branding from API error text before showing it in alerts.
    static func scrubVendorBranding(_ text: String) -> String {
        var s = text
        let replacements: [(String, String)] = [
            ("OpenAI", "Speech service"),
            ("openai", "speech service"),
            ("GPT", "speech"),
            ("gpt-", "speech-"),
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to)
        }
        return s
    }

    private static func friendlyMessage(httpStatus: Int, body: String) -> String {
        let parsed = parseOpenAIErrorBody(body)
        if parsed.code == "insufficient_quota" || parsed.type == "insufficient_quota" {
            return "Speech service has no remaining balance or quota. Add credits in your billing settings, then try Perform again."
        }
        switch httpStatus {
        case 401:
            return "API key is invalid or revoked. Update it under Performance settings."
        case 403:
            return "This API key was rejected (access denied). Check the key and your project permissions."
        case 429:
            if parsed.message.lowercased().contains("quota") || parsed.message.lowercased().contains("billing") {
                return "Quota or billing limit reached. Check your account balance, then try Perform again."
            }
            return "Rate limit reached. Wait a moment and try Perform again."
        case 500...599:
            return "Speech service is temporarily unavailable (HTTP \(httpStatus)). Try Perform again in a minute."
        default:
            if !parsed.message.isEmpty { return scrubVendorBranding(parsed.message) }
            return "Connection failed (HTTP \(httpStatus)). Check your key and network, then try again."
        }
    }

    private static func friendlyMessage(error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "No internet connection. Connect to Wi‑Fi or cellular data, then try Perform again."
            case .timedOut:
                return "Connection timed out. Check your network and try Perform again."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Can't reach the speech service. Check your network or VPN, then try Perform again."
            default:
                break
            }
        }
        let detail = scrubVendorBranding(error.localizedDescription)
        return "Couldn't connect (\(detail)). Check your network and API key."
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
