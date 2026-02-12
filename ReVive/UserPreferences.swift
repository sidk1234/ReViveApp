//
//  UserPreferences.swift
//  Recyclability
//

import Foundation

struct UserPreferences: Codable, Equatable {
    var defaultZip: String?
    var appearanceMode: AppAppearanceMode?
    var enableHaptics: Bool?
    var showCaptureInstructions: Bool?
    var autoSyncImpact: Bool?
    var allowWebSearch: Bool?
    var reduceMotion: Bool?

    static let `default` = UserPreferences(
        defaultZip: nil,
        appearanceMode: nil,
        enableHaptics: nil,
        showCaptureInstructions: nil,
        autoSyncImpact: nil,
        allowWebSearch: nil,
        reduceMotion: nil
    )

    var hasAnyValue: Bool {
        let zipValue = defaultZip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !zipValue.isEmpty ||
            appearanceMode != nil ||
            enableHaptics != nil ||
            showCaptureInstructions != nil ||
            autoSyncImpact != nil ||
            allowWebSearch != nil ||
            reduceMotion != nil
    }

    static func from(metadata: [String: Any]?) -> UserPreferences? {
        guard
            let metadata,
            let prefs = metadata["preferences"] as? [String: Any]
        else { return nil }

        var result = UserPreferences.default
        var hasValue = false

        if let zip = prefs["default_zip"] as? String {
            result.defaultZip = zip
            hasValue = true
        }
        if let mode = prefs["appearance"] as? String,
           let appearance = AppAppearanceMode(rawValue: mode) {
            result.appearanceMode = appearance
            hasValue = true
        }
        if let enableHaptics = prefs["enable_haptics"] as? Bool {
            result.enableHaptics = enableHaptics
            hasValue = true
        }
        if let showInstructions = prefs["show_capture_instructions"] as? Bool {
            result.showCaptureInstructions = showInstructions
            hasValue = true
        }
        if let autoSyncImpact = prefs["auto_sync_impact"] as? Bool {
            result.autoSyncImpact = autoSyncImpact
            hasValue = true
        }
        if let allowWebSearch = prefs["allow_web_search"] as? Bool {
            result.allowWebSearch = allowWebSearch
            hasValue = true
        }
        if let reduceMotion = prefs["reduce_motion"] as? Bool {
            result.reduceMotion = reduceMotion
            hasValue = true
        }

        return hasValue ? result : nil
    }

    func metadataPayload() -> [String: Any] {
        var payload: [String: Any] = [:]

        if let defaultZip {
            payload["default_zip"] = defaultZip
        }
        if let appearanceMode {
            payload["appearance"] = appearanceMode.rawValue
        }
        if let enableHaptics {
            payload["enable_haptics"] = enableHaptics
        }
        if let showCaptureInstructions {
            payload["show_capture_instructions"] = showCaptureInstructions
        }
        if let autoSyncImpact {
            payload["auto_sync_impact"] = autoSyncImpact
        }
        if let allowWebSearch {
            payload["allow_web_search"] = allowWebSearch
        }
        if let reduceMotion {
            payload["reduce_motion"] = reduceMotion
        }

        guard !payload.isEmpty else { return [:] }
        return ["preferences": payload]
    }
}
