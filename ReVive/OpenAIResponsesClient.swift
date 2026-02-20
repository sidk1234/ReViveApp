//
//  OpenAIResponsesClient.swift
//  Recyclability
//
//  Created by Sidharth Kumar on 1/25/26.
//


import Foundation
import UIKit

struct SignedInQuotaUpdate {
    let remaining: Int?
    let limit: Int
    let isPro: Bool?
    let monthKey: String?
}

// Minimal client for the Supabase Edge proxy
final class OpenAIResponsesClient {
    private var edgeOpenAIURL: URL? {
        guard let base = SupabaseConfig.load()?.url else { return nil }
        return base.appendingPathComponent("functions/v1/revive")
    }

    struct ProxyRequest: Encodable {
        let mode: String
        let image: String?
        let contextImage: String?
        let itemText: String?
        let latitude: Double?
        let longitude: Double?
        let locality: String?
        let administrativeArea: String?
        let postalCode: String?
        let countryCode: String?
        let deviceId: String?
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
        image: UIImage,
        contextImage: UIImage? = nil,
        itemText: String? = nil,
        location: LocationContext?,
        accessToken: String?
    ) async throws -> String {

        guard let url = edgeOpenAIURL else { throw OpenAIError.invalidURL }
        let anonKey = SupabaseConfig.load()?.anonKey

        // Compress before upload to reduce payload size and latency.
        guard let dataURL = image.compressedJPEGDataURL(maxDimension: 1400, quality: 0.7) else {
            throw OpenAIError.invalidImage
        }
        let contextDataURL = contextImage?.compressedJPEGDataURL(maxDimension: 1100, quality: 0.65)

        let body = ProxyRequest(
            mode: "image",
            image: dataURL,
            contextImage: contextDataURL,
            itemText: itemText,
            latitude: location?.latitude,
            longitude: location?.longitude,
            locality: location?.locality,
            administrativeArea: location?.administrativeArea,
            postalCode: location?.postalCode,
            countryCode: location?.countryCode,
            deviceId: DeviceIDStore.current
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
        logBackendHeaders(http, mode: "image")
        notifyGuestQuotaIfNeeded(http)
        notifySignedInQuotaIfNeeded(http)

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
        itemText: String,
        location: LocationContext?,
        accessToken: String?
    ) async throws -> String {

        guard let url = edgeOpenAIURL else { throw OpenAIError.invalidURL }
        let anonKey = SupabaseConfig.load()?.anonKey

        let body = ProxyRequest(
            mode: "text",
            image: nil,
            contextImage: nil,
            itemText: itemText,
            latitude: location?.latitude,
            longitude: location?.longitude,
            locality: location?.locality,
            administrativeArea: location?.administrativeArea,
            postalCode: location?.postalCode,
            countryCode: location?.countryCode,
            deviceId: DeviceIDStore.current
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
        logBackendHeaders(http, mode: "text")
        notifyGuestQuotaIfNeeded(http)
        notifySignedInQuotaIfNeeded(http)

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
    request.setValue(DeviceIDStore.current, forHTTPHeaderField: "x-revive-device-id")
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

private func notifySignedInQuotaIfNeeded(_ response: HTTPURLResponse) {
    let isProHeader = response.value(forHTTPHeaderField: "x-revive-signed-is-pro")
    let remainingHeader = response.value(forHTTPHeaderField: "x-revive-signed-remaining")
    let limitHeader = response.value(forHTTPHeaderField: "x-revive-signed-limit")
    let monthHeader = response.value(forHTTPHeaderField: "x-revive-signed-month")

    guard isProHeader != nil || remainingHeader != nil || limitHeader != nil else { return }

    let isPro: Bool? = {
        guard let raw = isProHeader?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !raw.isEmpty else { return nil }
        if raw == "true" || raw == "1" || raw == "yes" { return true }
        if raw == "false" || raw == "0" || raw == "no" { return false }
        return nil
    }()
    let limit = max(1, Int(limitHeader ?? "") ?? 25)
    let remainingValue = Int(remainingHeader ?? "")
    let update = SignedInQuotaUpdate(
        remaining: (isPro == true) ? nil : max(0, remainingValue ?? 0),
        limit: limit,
        isPro: isPro,
        monthKey: monthHeader
    )
    NotificationCenter.default.post(name: .reviveSignedQuotaUpdated, object: update)
}

private func logBackendHeaders(_ response: HTTPURLResponse, mode: String) {
    let backend = response.value(forHTTPHeaderField: "x-revive-backend") ?? "missing"
    let requestId = response.value(forHTTPHeaderField: "x-revive-request-id") ?? "missing"
    print("[ReViveAI] mode=\(mode) backend=\(backend) request_id=\(requestId) status=\(response.statusCode)")
}

extension Notification.Name {
    static let reviveGuestQuotaUpdated = Notification.Name("revive.guestQuotaUpdated")
    static let reviveSignedQuotaUpdated = Notification.Name("revive.signedQuotaUpdated")
    static let reviveRequestSignIn = Notification.Name("revive.requestSignIn")
    static let reviveRequestUpgrade = Notification.Name("revive.requestUpgrade")
    static let reviveOpenSubscription = Notification.Name("revive.openSubscription")
    static let reviveBillingSuccess = Notification.Name("revive.billingSuccess")
    static let reviveBillingError = Notification.Name("revive.billingError")
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
