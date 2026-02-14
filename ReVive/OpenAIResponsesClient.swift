//
//  OpenAIResponsesClient.swift
//  Recyclability
//
//  Created by Sidharth Kumar on 1/25/26.
//


import Foundation
import UIKit

// Minimal client for the Supabase Edge proxy
final class OpenAIResponsesClient {
    private var edgeOpenAIURL: URL? {
        guard let base = SupabaseConfig.load()?.url else { return nil }
        return base.appendingPathComponent("functions/v1/revive")
    }

    private let imageModel = "gpt-4o-mini"
    private let textModel = "gpt-4o-mini-search-preview"

    struct ProxyRequest: Encodable {
        let mode: String
        let model: String
        let prompt: String
        let image: String?
        let contextImage: String?
        let maxOutputTokens: Int?
        let useWebSearch: Bool?
    }

    struct ProxyResponse: Decodable {
        let text: String
    }

    enum OpenAIError: Error, LocalizedError {
        case invalidURL
        case invalidImage
        case httpError(Int, String)
        case noTextReturned

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid AI proxy URL."
            case .invalidImage: return "Could not encode image."
            case .httpError(let code, let msg): return "AI proxy HTTP \(code): \(msg)"
            case .noTextReturned: return "No text returned from model."
            }
        }
    }

    func analyzeImage(
        prompt: String,
        image: UIImage,
        contextImage: UIImage? = nil,
        maxOutputTokens: Int = 300,
        useWebSearch: Bool = false,
        accessToken: String?
    ) async throws -> String {

        guard let url = edgeOpenAIURL else { throw OpenAIError.invalidURL }
        let anonKey = SupabaseConfig.load()?.anonKey

        // Base64 data URL is supported for image input. :contentReference[oaicite:3]{index=3}
        guard let dataURL = image.jpegDataURL(compressionQuality: 0.9) else {
            throw OpenAIError.invalidImage
        }
        let contextDataURL = contextImage?.jpegDataURL(compressionQuality: 0.9)

        let body = ProxyRequest(
            mode: "image",
            model: imageModel,
            prompt: prompt,
            image: dataURL,
            contextImage: contextDataURL,
            maxOutputTokens: maxOutputTokens,
            useWebSearch: useWebSearch
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&request, accessToken: accessToken, anonKey: anonKey)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(-1, "No HTTP response")
        }
        notifyGuestQuotaIfNeeded(http)

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "(no body)"
            throw OpenAIError.httpError(http.statusCode, msg)
        }

        if let decoded = try? JSONDecoder().decode(ProxyResponse.self, from: data) {
            let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let extracted = extractText(from: data) {
            return extracted
        }

        throw OpenAIError.noTextReturned
    }

    func analyzeText(
        prompt: String,
        maxOutputTokens: Int = 300,
        useWebSearch: Bool = false,
        accessToken: String?
    ) async throws -> String {

        guard let url = edgeOpenAIURL else { throw OpenAIError.invalidURL }
        let anonKey = SupabaseConfig.load()?.anonKey

        _ = useWebSearch
        let body = ProxyRequest(
            mode: "text",
            model: textModel,
            prompt: prompt,
            image: nil,
            contextImage: nil,
            maxOutputTokens: maxOutputTokens,
            useWebSearch: useWebSearch
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&request, accessToken: accessToken, anonKey: anonKey)
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw OpenAIError.httpError(-1, "No HTTP response")
        }
        notifyGuestQuotaIfNeeded(http)

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "(no body)"
            throw OpenAIError.httpError(http.statusCode, msg)
        }

        if let decoded = try? JSONDecoder().decode(ProxyResponse.self, from: data) {
            let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let extracted = extractText(from: data) {
            return extracted
        }

        throw OpenAIError.noTextReturned
    }
}

private func applyAuthHeaders(_ request: inout URLRequest, accessToken: String?, anonKey: String?) {
    if let accessToken, !accessToken.isEmpty {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    } else if let anonKey, !anonKey.isEmpty {
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    }
    if let anonKey, !anonKey.isEmpty {
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
    }
}

private func notifyGuestQuotaIfNeeded(_ response: HTTPURLResponse) {
    guard
        let remainingValue = response.value(forHTTPHeaderField: "x-revive-guest-remaining"),
        let usedValue = response.value(forHTTPHeaderField: "x-revive-guest-used"),
        let limitValue = response.value(forHTTPHeaderField: "x-revive-guest-limit"),
        let remaining = Int(remainingValue),
        let used = Int(usedValue),
        let limit = Int(limitValue)
    else { return }

    let quota = GuestQuota(used: used, remaining: remaining, limit: limit)
    NotificationCenter.default.post(name: .reviveGuestQuotaUpdated, object: quota)
}

extension Notification.Name {
    static let reviveGuestQuotaUpdated = Notification.Name("revive.guestQuotaUpdated")
    static let reviveRequestSignIn = Notification.Name("revive.requestSignIn")
}

private func extractText(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }

    func extractFromChatChoices(_ value: Any) -> String? {
        guard let dict = value as? [String: Any],
              let choices = dict["choices"] as? [[String: Any]]
        else { return nil }
        for choice in choices {
            if let message = choice["message"] as? [String: Any],
               let content = message["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    func findText(_ value: Any) -> String? {
        if let str = value as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let dict = value as? [String: Any] {
            if let fromChoices = extractFromChatChoices(dict) {
                return fromChoices
            }
            let keys = ["text", "output_text", "content", "message", "result"]
            for key in keys {
                if let candidate = dict[key], let found = findText(candidate) {
                    return found
                }
            }
            for (_, v) in dict {
                if let found = findText(v) { return found }
            }
        }
        if let array = value as? [Any] {
            for v in array {
                if let found = findText(v) { return found }
            }
        }
        return nil
    }

    return findText(json)
}

private extension UIImage {
    func jpegDataURL(compressionQuality: CGFloat) -> String? {
        guard let data = self.jpegData(compressionQuality: compressionQuality) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }
}
