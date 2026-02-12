//
//  SupabaseService.swift
//  Recyclability
//

import Foundation

struct SupabaseConfig {
    let url: URL
    let anonKey: String

    static func load() -> SupabaseConfig? {
        guard let config = AppConfigCache.load(),
              !config.supabaseURL.isEmpty,
              !config.supabaseAnonKey.isEmpty,
              let url = URL(string: config.supabaseURL)
        else {
            return nil
        }
        return SupabaseConfig(url: url, anonKey: config.supabaseAnonKey)
    }

    static func diagnostics() -> (summary: String, short: String) {
        var summaryParts: [String] = []
        var shortParts: [String] = []

        if let edgeBaseURL = BootstrapConfig.edgeBaseURL?.absoluteString, !edgeBaseURL.isEmpty {
            summaryParts.append("EDGE_BASE_URL=\(edgeBaseURL)")
        } else {
            summaryParts.append("EDGE_BASE_URL missing")
            shortParts.append("edge base URL missing")
        }

        guard let cached = AppConfigCache.load() else {
            summaryParts.append("config cache missing")
            if let failure = AppConfigCache.loadFailure(), !failure.isEmpty {
                summaryParts.append("last config error=\(failure)")
                shortParts.append(failure)
            } else {
                shortParts.append("app config not loaded")
            }
            return (summaryParts.joined(separator: " | "), shortParts.joined(separator: "; "))
        }

        summaryParts.append("config cache present")

        if cached.supabaseURL.isEmpty {
            summaryParts.append("supabaseURL empty")
            shortParts.append("supabase URL missing")
        } else if let url = URL(string: cached.supabaseURL) {
            summaryParts.append("supabaseURL host=\(url.host ?? "unknown")")
        } else {
            summaryParts.append("supabaseURL invalid")
            shortParts.append("supabase URL invalid")
        }

        if cached.supabaseAnonKey.isEmpty {
            summaryParts.append("supabaseAnonKey empty")
            shortParts.append("supabase anon key missing")
        } else {
            summaryParts.append("supabaseAnonKey present")
        }

        if cached.googleIOSClientID.isEmpty {
            summaryParts.append("googleIOSClientID empty")
        } else {
            summaryParts.append("googleIOSClientID present")
        }

        if cached.googleWebClientID.isEmpty {
            summaryParts.append("googleWebClientID empty")
        } else {
            summaryParts.append("googleWebClientID present")
        }

        if cached.googleReversedClientID.isEmpty {
            summaryParts.append("googleReversedClientID empty")
        } else {
            summaryParts.append("googleReversedClientID present")
        }

        if let cachedHost = URL(string: cached.supabaseURL)?.host,
           let edgeHost = BootstrapConfig.edgeBaseURL?.host,
           cachedHost != edgeHost {
            summaryParts.append("host mismatch (cached=\(cachedHost), edge=\(edgeHost))")
            shortParts.append("edge base URL differs from cached config")
        }

        if let failure = AppConfigCache.loadFailure(), !failure.isEmpty {
            summaryParts.append("last config error=\(failure)")
        }

        if shortParts.isEmpty {
            shortParts.append("unknown configuration state")
        }

        return (summaryParts.joined(separator: " | "), shortParts.joined(separator: "; "))
    }
}

struct SupabaseSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

struct SupabaseUser: Equatable {
    let id: String
    let email: String?
    let displayName: String?
    let preferences: UserPreferences?
}

struct AppSettings: Decodable {
    let photoStorageEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case photoStorageEnabled = "photo_storage_enabled"
    }
}

struct ProfileRow: Identifiable, Decodable {
    let id: String
    let displayName: String?
    let email: String?
    let isAdmin: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "full_name"
        case email
        case isAdmin = "is_admin"
    }
}

struct ImpactEntryRow: Identifiable, Decodable {
    let rowId: String?
    let userId: String
    let itemKey: String
    let dayKey: String
    let item: String
    let material: String
    let recyclable: Bool
    let bin: String
    let notes: String
    let scannedAt: String
    let points: Int
    let scanCount: Int?
    let source: String?
    let imagePath: String?

    private enum CodingKeys: String, CodingKey {
        case rowId = "id"
        case userId = "user_id"
        case itemKey = "item_key"
        case dayKey = "day_key"
        case item
        case material
        case recyclable
        case bin
        case notes
        case scannedAt = "scanned_at"
        case points
        case scanCount = "scan_count"
        case source
        case imagePath = "image_path"
    }

    var id: String {
        rowId ?? "\(userId)|\(itemKey)"
    }
}

struct ImpactPayload: Codable {
    let user_id: String
    let item_key: String
    let day_key: String
    let item: String
    let material: String
    let recyclable: Bool
    let bin: String
    let notes: String
    let scanned_at: String
    let points: Int
    let scan_count: Int
    let image_path: String?
    let source: String?
}

struct LeaderboardEntry: Identifiable, Decodable {
    let userId: String
    let displayName: String?
    let totalPoints: Int
    let recyclableCount: Int?
    let totalScans: Int?

    var id: String { userId }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case totalPoints = "total_points"
        case recyclableCount = "recyclable_count"
        case totalScans = "total_scans"
    }
}

struct GuestQuota: Codable, Equatable {
    let used: Int
    let remaining: Int
    let limit: Int
}

final class SupabaseService {
    enum ServiceError: Error {
        case invalidResponse
        case httpError(Int, String)
        case invalidCallback
        case missingConfig
    }

    private let config: SupabaseConfig
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double

        private enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private struct SignUpResponse: Decodable {
        let session: TokenResponse?
    }

    init(config: SupabaseConfig) {
        self.config = config
        jsonEncoder.outputFormatting = []
    }

    var baseURL: URL { config.url }

    var anonKey: String { config.anonKey }

    func makeOAuthURL(provider: String, redirectURL: String) -> URL? {
        var components = URLComponents(url: config.url.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "provider", value: provider),
            URLQueryItem(name: "redirect_to", value: redirectURL),
            URLQueryItem(name: "response_type", value: "token")
        ]
        return components?.url
    }

    func signInWithIDToken(provider: String, idToken: String, nonce: String?) async throws -> SupabaseSession {
        let url = config.url.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "id_token")]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        var body: [String: Any] = [
            "provider": provider,
            "id_token": idToken
        ]
        if let nonce { body["nonce"] = nonce }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }

        let decoded = try jsonDecoder.decode(TokenResponse.self, from: data)
        return makeSession(from: decoded)
    }

    func signInWithEmail(email: String, password: String) async throws -> SupabaseSession {
        let url = config.url.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        let payload: [String: Any] = [
            "email": email,
            "password": password
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }

        let decoded = try jsonDecoder.decode(TokenResponse.self, from: data)
        return makeSession(from: decoded)
    }

    func signUpWithEmail(email: String, password: String) async throws -> SupabaseSession? {
        let url = config.url.appendingPathComponent("auth/v1/signup")
        let payload: [String: Any] = [
            "email": email,
            "password": password
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }

        let decoded = try jsonDecoder.decode(SignUpResponse.self, from: data)
        guard let session = decoded.session else { return nil }
        return makeSession(from: session)
    }

    func sendPasswordReset(email: String) async throws {
        let url = config.url.appendingPathComponent("auth/v1/recover")
        let payload: [String: Any] = [
            "email": email
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
    }

    func fetchGuestQuota() async throws -> GuestQuota {
        let url = config.url.appendingPathComponent("functions/v1/anon-quota")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(config.anonKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
        return try jsonDecoder.decode(GuestQuota.self, from: data)
    }

    func deleteAccount(accessToken: String) async throws {
        let url = config.url.appendingPathComponent("functions/v1/delete-account")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
    }

    func parseOAuthCallback(_ url: URL) -> SupabaseSession? {
        let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.query
        let items = parseQueryItems(fragment ?? query ?? "")
        guard
            let accessToken = items["access_token"],
            let refreshToken = items["refresh_token"],
            let expiresInValue = items["expires_in"],
            let expiresIn = Double(expiresInValue)
        else { return nil }

        let expiresAt = Date().addingTimeInterval(expiresIn)
        return SupabaseSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    func refreshSession(refreshToken: String) async throws -> SupabaseSession {
        let url = config.url.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let refreshURL = components?.url else { throw ServiceError.invalidCallback }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }

        guard
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = dict["access_token"] as? String,
            let refreshToken = dict["refresh_token"] as? String,
            let expiresIn = dict["expires_in"] as? Double
        else { throw ServiceError.invalidResponse }

        let expiresAt = Date().addingTimeInterval(expiresIn)
        return SupabaseSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    func fetchUser(accessToken: String) async throws -> SupabaseUser {
        let url = config.url.appendingPathComponent("auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }

        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = dict["id"] as? String
        else { throw ServiceError.invalidResponse }

        let email = dict["email"] as? String
        let metadata = dict["user_metadata"] as? [String: Any]
        let displayName =
            metadata?["full_name"] as? String ??
            metadata?["name"] as? String ??
            metadata?["preferred_username"] as? String
        let preferences = UserPreferences.from(metadata: metadata)

        return SupabaseUser(id: id, email: email, displayName: displayName, preferences: preferences)
    }

    func updateUserPreferences(_ preferences: UserPreferences, accessToken: String) async throws {
        let metadata = preferences.metadataPayload()
        try await updateUserMetadata(metadata, accessToken: accessToken)
    }

    func updateUserDisplayName(_ displayName: String, accessToken: String) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await updateUserMetadata(["full_name": trimmed], accessToken: accessToken)
    }

    private func updateUserMetadata(_ metadata: [String: Any], accessToken: String) async throws {
        guard !metadata.isEmpty else { return }
        let url = config.url.appendingPathComponent("auth/v1/user")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let payload: [String: Any] = ["data": metadata]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
    }

    func upsertProfile(user: SupabaseUser, accessToken: String) async throws {
        let url = config.url.appendingPathComponent("rest/v1/profiles")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        let displayName = user.displayName ?? user.email?.components(separatedBy: "@").first ?? "Recycler"
        let payload: [String: Any] = [
            "id": user.id,
            "full_name": displayName,
            "email": user.email ?? "",
            "updated_at": isoTimestamp(Date())
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
    }

    func fetchProfile(id: String, accessToken: String) async throws -> ProfileRow? {
        let url = config.url.appendingPathComponent("rest/v1/profiles")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "id,full_name,email,is_admin"),
            URLQueryItem(name: "id", value: "eq.\(id)"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
        let rows = try jsonDecoder.decode([ProfileRow].self, from: data)
        return rows.first
    }

    func fetchProfiles(accessToken: String, limit: Int = 60) async throws -> [ProfileRow] {
        let url = config.url.appendingPathComponent("rest/v1/profiles")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "id,full_name,email,is_admin,updated_at"),
            URLQueryItem(name: "order", value: "updated_at.desc"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
        return try jsonDecoder.decode([ProfileRow].self, from: data)
    }

    func updateProfile(
        id: String,
        displayName: String,
        email: String,
        accessToken: String
    ) async throws {
        let url = config.url.appendingPathComponent("rest/v1/profiles")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        let payload: [String: Any] = [
            "full_name": displayName,
            "email": email,
            "updated_at": isoTimestamp(Date())
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw ServiceError.httpError(http.statusCode, "Profile update failed")
        }
    }

    func updateProfileAdminStatus(id: String, isAdmin: Bool, accessToken: String) async throws {
        let url = config.url.appendingPathComponent("rest/v1/profiles")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        let payload: [String: Any] = [
            "is_admin": isAdmin,
            "updated_at": isoTimestamp(Date())
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw ServiceError.httpError(http.statusCode, "Admin update failed")
        }
    }

    func insertImpact(payload: ImpactPayload, accessToken: String) async throws -> Bool {
        let url = config.url.appendingPathComponent("rest/v1/impact_entries")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // De-dupe per user + item + day, so rescans update scan_count rather than creating new rows.
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: "user_id,item_key,day_key")]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try jsonEncoder.encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        if http.statusCode == 409 || http.statusCode == 406 {
            return false
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }

        let trimmed = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed == "[]" { return false }
        return true
    }

    func fetchImpactEntries(accessToken: String, limit: Int = 60) async throws -> [ImpactEntryRow] {
        let url = config.url.appendingPathComponent("rest/v1/impact_entries")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(
                name: "select",
                value: "id,user_id,item_key,day_key,item,material,recyclable,bin,notes,scanned_at,points,scan_count,source,image_path"
            ),
            URLQueryItem(name: "order", value: "scanned_at.desc"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
        return try jsonDecoder.decode([ImpactEntryRow].self, from: data)
    }

    func updateImpactEntry(
        originalUserId: String,
        originalItemKey: String,
        originalDayKey: String,
        updated: ImpactEntryRow,
        accessToken: String
    ) async throws {
        let url = config.url.appendingPathComponent("rest/v1/impact_entries")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(originalUserId)"),
            URLQueryItem(name: "item_key", value: "eq.\(originalItemKey)"),
            URLQueryItem(name: "day_key", value: "eq.\(originalDayKey)")
        ]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        let payload: [String: Any] = [
            "item": updated.item,
            "material": updated.material,
            "recyclable": updated.recyclable,
            "bin": updated.bin,
            "notes": updated.notes,
            "points": updated.points,
            "source": updated.source ?? "",
            "item_key": updated.itemKey,
            "updated_at": isoTimestamp(Date())
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw ServiceError.httpError(http.statusCode, "Impact update failed")
        }
    }

    func deleteImpactEntry(
        userId: String,
        itemKey: String,
        dayKey: String,
        accessToken: String
    ) async throws {
        let url = config.url.appendingPathComponent("rest/v1/impact_entries")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "item_key", value: "eq.\(itemKey)"),
            URLQueryItem(name: "day_key", value: "eq.\(dayKey)")
        ]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "DELETE"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw ServiceError.httpError(http.statusCode, "Impact delete failed")
        }
    }

    func fetchLeaderboard(accessToken: String?) async throws -> [LeaderboardEntry] {
        let url = config.url.appendingPathComponent("rest/v1/impact_leaderboard")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "user_id,display_name,total_points,recyclable_count,total_scans"),
            URLQueryItem(name: "order", value: "total_points.desc"),
            URLQueryItem(name: "limit", value: "50")
        ]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
        return try jsonDecoder.decode([LeaderboardEntry].self, from: data)
    }

    func fetchAppSettings(accessToken: String?) async throws -> AppSettings? {
        let url = config.url.appendingPathComponent("rest/v1/app_settings")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "select", value: "photo_storage_enabled"),
            URLQueryItem(name: "id", value: "eq.1"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw ServiceError.httpError(http.statusCode, msg)
        }
        let rows = try jsonDecoder.decode([AppSettings].self, from: data)
        return rows.first
    }

    func upsertAppSettings(photoStorageEnabled: Bool, accessToken: String) async throws {
        let url = config.url.appendingPathComponent("rest/v1/app_settings")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        guard let requestURL = components?.url else { throw ServiceError.invalidCallback }

        let payload: [String: Any] = [
            "id": 1,
            "photo_storage_enabled": photoStorageEnabled,
            "updated_at": isoTimestamp(Date())
        ]

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw ServiceError.httpError(http.statusCode, "Settings update failed")
        }
    }

    func uploadImpactImage(data: Data, path: String, accessToken: String) async throws {
        let bucket = "impact-images"
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = config.url.appendingPathComponent("storage/v1/object/\(bucket)/\(encodedPath)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw ServiceError.httpError(http.statusCode, "Image upload failed")
        }
    }

    private func parseQueryItems(_ raw: String) -> [String: String] {
        raw
            .split(separator: "&")
            .reduce(into: [:]) { result, part in
                let parts = part.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let key = parts[0].removingPercentEncoding ?? parts[0]
                    let value = parts[1].removingPercentEncoding ?? parts[1]
                    result[key] = value
                }
            }
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func makeSession(from token: TokenResponse) -> SupabaseSession {
        let expiresAt = Date().addingTimeInterval(token.expiresIn)
        return SupabaseSession(accessToken: token.accessToken, refreshToken: token.refreshToken, expiresAt: expiresAt)
    }
}
