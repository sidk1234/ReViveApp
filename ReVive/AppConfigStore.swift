//
//  AppConfigStore.swift
//  Recyclability
//

import Foundation
import Combine

struct AppConfig: Codable, Equatable {
    let supabaseURL: String
    let supabaseAnonKey: String
    let googleIOSClientID: String
    let googleWebClientID: String
    let googleReversedClientID: String
}

enum AppConfigCache {
    private static let storageKey = "recai.app.config"
    private static let failureKey = "recai.app.config.failure"
    private static let timestampKey = "recai.app.config.timestamp"

    static func load() -> AppConfig? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    static func save(_ config: AppConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: timestampKey)
        clearFailure()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: timestampKey)
        clearFailure()
    }

    static func saveFailure(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: failureKey)
    }

    static func loadFailure() -> String? {
        UserDefaults.standard.string(forKey: failureKey)
    }

    static func clearFailure() {
        UserDefaults.standard.removeObject(forKey: failureKey)
    }

    static func loadTimestamp() -> Date? {
        let interval = UserDefaults.standard.double(forKey: timestampKey)
        guard interval > 0 else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    static func isFresh(maxAge: TimeInterval) -> Bool {
        guard let timestamp = loadTimestamp() else { return false }
        return Date().timeIntervalSince(timestamp) < maxAge
    }
}

enum BootstrapConfig {
    static var edgeBaseURL: URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "EDGE_BASE_URL") as? String,
            !value.isEmpty
        else { return nil }
        return URL(string: value)
    }

    static var edgeAnonKey: String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "EDGE_ANON_KEY") as? String,
            !value.isEmpty
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
    }
}

@MainActor
final class AppConfigStore: ObservableObject {
    @Published private(set) var config: AppConfig?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private static let configFunctionCandidates = [
        "revive-ios"
    ]

    private enum AppConfigLog {
        static func info(_ message: String) { print("[AppConfig] \(message)") }
        static func warn(_ message: String) { print("[AppConfig] WARN: \(message)") }
        static func error(_ message: String) { print("[AppConfig] ERROR: \(message)") }
    }

    func load(force: Bool = false) async {
        let cached = AppConfigCache.load()
        if !force, let cached {
            config = cached
            AppConfigLog.info("Using cached config.")
        }

        let baseURL = BootstrapConfig.edgeBaseURL
        if let cached,
           let baseURL,
           let cachedHost = URL(string: cached.supabaseURL)?.host,
           let baseHost = baseURL.host,
           cachedHost != baseHost {
            AppConfigCache.clear()
            config = nil
            let message = "Cached config host mismatch (cached=\(cachedHost), edge=\(baseHost)). Cache cleared."
            AppConfigCache.saveFailure(message)
            AppConfigLog.warn(message)
        }

        if !force, cached != nil, AppConfigCache.isFresh(maxAge: 12 * 60 * 60) {
            return
        }

        guard let baseURL else {
            if config == nil {
                let message = "Missing edge base URL."
                errorMessage = message
                AppConfigCache.saveFailure(message)
                AppConfigLog.error(message)
            }
            return
        }

        isLoading = true
        defer { isLoading = false }

        var lastError: String?
        for functionName in Self.configFunctionCandidates {
            let endpoint = baseURL.appendingPathComponent("functions/v1/\(functionName)")
            AppConfigLog.info("Fetching config from \(endpoint.absoluteString)")
            do {
                var request = URLRequest(url: endpoint)
                request.httpMethod = "GET"
                if let anonKey = BootstrapConfig.edgeAnonKey {
                    request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
                    request.setValue(anonKey, forHTTPHeaderField: "apikey")
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    let message = "Invalid config response."
                    lastError = message
                    AppConfigLog.error(message)
                    continue
                }

                if http.statusCode == 404 {
                    let message = "Config function not found (\(functionName))."
                    lastError = message
                    AppConfigLog.warn("HTTP 404 from \(functionName).")
                    continue
                }

                guard (200...299).contains(http.statusCode) else {
                    let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                    let errorMessage = "Config fetch failed (\(http.statusCode)): \(message)"
                    lastError = errorMessage
                    AppConfigLog.error(errorMessage)
                    continue
                }

                let decoded = try JSONDecoder().decode(RemoteConfigResponse.self, from: data)
                let hasSupabaseURL = !(decoded.supabaseURL ?? "").isEmpty
                let hasSupabaseAnonKey = !(decoded.supabaseAnonKey ?? "").isEmpty
                let hasGoogleIOS = !(decoded.googleIOSClientID ?? "").isEmpty
                let hasGoogleWeb = !(decoded.googleWebClientID ?? "").isEmpty
                let hasGoogleReversed = !(decoded.googleReversedClientID ?? "").isEmpty
                AppConfigLog.info(
                    "Config response parsed. supabaseURL=\(hasSupabaseURL) supabaseAnonKey=\(hasSupabaseAnonKey) " +
                    "googleIOSClientID=\(hasGoogleIOS) googleWebClientID=\(hasGoogleWeb) googleReversedClientID=\(hasGoogleReversed)"
                )
                let config = AppConfig(
                    supabaseURL: decoded.supabaseURL ?? "",
                    supabaseAnonKey: decoded.supabaseAnonKey ?? "",
                    googleIOSClientID: decoded.googleIOSClientID ?? "",
                    googleWebClientID: decoded.googleWebClientID ?? "",
                    googleReversedClientID: decoded.googleReversedClientID ?? ""
                )

                var missing: [String] = []
                if config.supabaseURL.isEmpty { missing.append("supabase_url") }
                if config.supabaseAnonKey.isEmpty { missing.append("supabase_anon_key") }
                if !missing.isEmpty {
                    let message = "Config missing required fields: \(missing.joined(separator: ", "))."
                    lastError = message
                    AppConfigLog.error(message)
                    continue
                }

                AppConfigCache.save(config)
                self.config = config
                errorMessage = nil
                AppConfigLog.info("Config cached successfully.")
                return
            } catch {
                let message = "Config fetch failed: \(error.localizedDescription)"
                lastError = message
                AppConfigLog.error(message)
                continue
            }
        }

        if let cached = AppConfigCache.load() {
            config = cached
        } else {
            let message = lastError ?? "Config fetch failed."
            errorMessage = message
            AppConfigCache.saveFailure(message)
            AppConfigLog.error(message)
        }
    }
}

private struct RemoteConfigResponse: Decodable {
    let supabaseURL: String?
    let supabaseAnonKey: String?
    let googleIOSClientID: String?
    let googleWebClientID: String?
    let googleReversedClientID: String?

    private enum CodingKeys: String, CodingKey {
        case supabaseURL = "supabase_url"
        case supabaseAnonKey = "supabase_anon_key"
        case googleIOSClientID = "google_ios_client_id"
        case googleWebClientID = "google_web_client_id"
        case googleReversedClientID = "google_reversed_client_id"
    }
}
