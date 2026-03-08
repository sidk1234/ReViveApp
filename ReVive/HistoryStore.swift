//
//  HistoryStore.swift
//  Recyclability
//

import Foundation
import Combine
import UIKit

enum HistorySource: String, Codable {
    case photo
    case text
}

enum RecycleEntryStatus: String, Codable {
    case markedForRecycle = "marked_for_recycle"
    case recycled = "recycled"
    case nonRecyclable = "non_recyclable"
}

private func normalizedDisposalLocation(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func inferredDisposalLocationFromRawPayload(_ rawPayload: String) -> String? {
    normalizedDisposalLocation(DisposalLocationFormatter.extractedFromRawPayload(rawPayload))
}

struct HistoryScan: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let item: String
    let material: String
    let recyclable: Bool
    let bin: String
    let notes: String
    let disposalLocation: String?
    let carbonSavedKg: Double
    let rawJSON: String
    let source: HistorySource
    let localImagePath: String?
    var remoteImagePath: String?

    init(
        id: UUID = UUID(),
        date: Date,
        item: String,
        material: String,
        recyclable: Bool,
        bin: String,
        notes: String,
        disposalLocation: String? = nil,
        carbonSavedKg: Double,
        rawJSON: String,
        source: HistorySource,
        localImagePath: String?,
        remoteImagePath: String?
    ) {
        self.id = id
        self.date = date
        self.item = item
        self.material = material
        self.recyclable = recyclable
        self.bin = bin
        self.notes = notes
        self.disposalLocation = normalizedDisposalLocation(disposalLocation)
        self.carbonSavedKg = max(0, carbonSavedKg)
        self.rawJSON = rawJSON
        self.source = source
        self.localImagePath = localImagePath
        self.remoteImagePath = remoteImagePath
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case item
        case material
        case recyclable
        case bin
        case notes
        case disposalLocation
        case disposal_location
        case location
        case carbonSavedKg
        case rawJSON
        case source
        case localImagePath
        case remoteImagePath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        item = try container.decode(String.self, forKey: .item)
        material = try container.decode(String.self, forKey: .material)
        recyclable = try container.decode(Bool.self, forKey: .recyclable)
        bin = try container.decode(String.self, forKey: .bin)
        notes = try container.decode(String.self, forKey: .notes)
        carbonSavedKg = max(0, try container.decodeIfPresent(Double.self, forKey: .carbonSavedKg) ?? 0)
        rawJSON = try container.decode(String.self, forKey: .rawJSON)
        source = (try? container.decode(HistorySource.self, forKey: .source)) ?? .photo
        localImagePath = try? container.decode(String.self, forKey: .localImagePath)
        remoteImagePath = try? container.decode(String.self, forKey: .remoteImagePath)
        let decodedLocationCandidates: [String?] = [
            try? container.decodeIfPresent(String.self, forKey: .disposalLocation),
            try? container.decodeIfPresent(String.self, forKey: .disposal_location),
            try? container.decodeIfPresent(String.self, forKey: .location),
            inferredDisposalLocationFromRawPayload(rawJSON)
        ]
        disposalLocation = decodedLocationCandidates.compactMap(normalizedDisposalLocation).first
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(item, forKey: .item)
        try container.encode(material, forKey: .material)
        try container.encode(recyclable, forKey: .recyclable)
        try container.encode(bin, forKey: .bin)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(disposalLocation, forKey: .disposalLocation)
        try container.encode(max(0, carbonSavedKg), forKey: .carbonSavedKg)
        try container.encode(rawJSON, forKey: .rawJSON)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(localImagePath, forKey: .localImagePath)
        try container.encodeIfPresent(remoteImagePath, forKey: .remoteImagePath)
    }
}

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let item: String
    let material: String
    let recyclable: Bool
    let bin: String
    let notes: String
    let disposalLocation: String?
    let carbonSavedKg: Double
    var recycleStatus: RecycleEntryStatus
    let rawJSON: String
    let source: HistorySource
    let localImagePath: String?
    var remoteImagePath: String?
    var scanCount: Int
    var scans: [HistoryScan]

    init(
        id: UUID,
        date: Date,
        item: String,
        material: String,
        recyclable: Bool,
        bin: String,
        notes: String,
        disposalLocation: String? = nil,
        carbonSavedKg: Double,
        recycleStatus: RecycleEntryStatus,
        rawJSON: String,
        source: HistorySource,
        localImagePath: String?,
        remoteImagePath: String?,
        scanCount: Int,
        scans: [HistoryScan]? = nil
    ) {
        self.id = id
        self.date = date
        self.item = item
        self.material = material
        self.recyclable = recyclable
        self.bin = bin
        self.notes = notes
        self.disposalLocation = normalizedDisposalLocation(disposalLocation)
        self.carbonSavedKg = max(0, carbonSavedKg)
        self.recycleStatus = recycleStatus
        self.rawJSON = rawJSON
        self.source = source
        self.localImagePath = localImagePath
        self.remoteImagePath = remoteImagePath
        self.scans = (scans?.isEmpty == false)
            ? scans!
            : [
                HistoryScan(
                    date: date,
                    item: item,
                    material: material,
                    recyclable: recyclable,
                    bin: bin,
                    notes: notes,
                    disposalLocation: self.disposalLocation,
                    carbonSavedKg: carbonSavedKg,
                    rawJSON: rawJSON,
                    source: source,
                    localImagePath: localImagePath,
                    remoteImagePath: remoteImagePath
                ),
            ]
        self.scanCount = max(scanCount, self.scans.count)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case item
        case material
        case recyclable
        case bin
        case notes
        case disposalLocation
        case disposal_location
        case location
        case carbonSavedKg
        case recycleStatus
        case rawJSON
        case source
        case localImagePath
        case remoteImagePath
        case scanCount
        case scans
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        item = try container.decode(String.self, forKey: .item)
        material = try container.decode(String.self, forKey: .material)
        recyclable = try container.decode(Bool.self, forKey: .recyclable)
        bin = try container.decode(String.self, forKey: .bin)
        notes = try container.decode(String.self, forKey: .notes)
        carbonSavedKg = max(0, try container.decodeIfPresent(Double.self, forKey: .carbonSavedKg) ?? 0)
        recycleStatus = (try? container.decode(RecycleEntryStatus.self, forKey: .recycleStatus))
            ?? (recyclable ? .recycled : .nonRecyclable)
        rawJSON = try container.decode(String.self, forKey: .rawJSON)
        let decodedLocationCandidates: [String?] = [
            try? container.decodeIfPresent(String.self, forKey: .disposalLocation),
            try? container.decodeIfPresent(String.self, forKey: .disposal_location),
            try? container.decodeIfPresent(String.self, forKey: .location),
            inferredDisposalLocationFromRawPayload(rawJSON)
        ]
        disposalLocation = decodedLocationCandidates.compactMap(normalizedDisposalLocation).first
        source = (try? container.decode(HistorySource.self, forKey: .source)) ?? .photo
        localImagePath = try? container.decode(String.self, forKey: .localImagePath)
        remoteImagePath = try? container.decode(String.self, forKey: .remoteImagePath)
        let decodedScans = try container.decodeIfPresent([HistoryScan].self, forKey: .scans) ?? []
        if decodedScans.isEmpty {
            scans = [
                HistoryScan(
                    date: date,
                    item: item,
                    material: material,
                    recyclable: recyclable,
                    bin: bin,
                    notes: notes,
                    disposalLocation: disposalLocation,
                    carbonSavedKg: carbonSavedKg,
                    rawJSON: rawJSON,
                    source: source,
                    localImagePath: localImagePath,
                    remoteImagePath: remoteImagePath
                ),
            ]
        } else {
            scans = decodedScans.sorted { $0.date > $1.date }
        }
        scanCount = max(try container.decodeIfPresent(Int.self, forKey: .scanCount) ?? 1, scans.count)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(item, forKey: .item)
        try container.encode(material, forKey: .material)
        try container.encode(recyclable, forKey: .recyclable)
        try container.encode(bin, forKey: .bin)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(disposalLocation, forKey: .disposalLocation)
        try container.encode(max(0, carbonSavedKg), forKey: .carbonSavedKg)
        try container.encode(recycleStatus, forKey: .recycleStatus)
        try container.encode(rawJSON, forKey: .rawJSON)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(localImagePath, forKey: .localImagePath)
        try container.encodeIfPresent(remoteImagePath, forKey: .remoteImagePath)
        try container.encode(scanCount, forKey: .scanCount)
        try container.encode(scans, forKey: .scans)
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published var entries: [HistoryEntry] = [] {
        didSet { save() }
    }

    enum InsertResult {
        case added(HistoryEntry)
        case duplicate(HistoryEntry)
    }

    private let legacyStorageKey = "recai.history.v1"
    private let guestStorageKey = "recai.history.v1.guest"
    private let userStorageKeyPrefix = "recai.history.v1.user."
    private let legacyStorageFilename = "impact-history.json"
    private let guestStorageFilename = "impact-history-guest.json"
    private let userStorageFilenamePrefix = "impact-history-user-"
    private var storageScope: StorageScope = .guest

    private enum StorageScope: Equatable {
        case guest
        case user(String)
    }

    init() {
        load()
    }

    func setStorageScope(userID: String?) {
        let normalized = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextScope: StorageScope
        if let normalized, !normalized.isEmpty {
            nextScope = .user(normalized)
        } else {
            nextScope = .guest
        }

        guard nextScope != storageScope else { return }
        save()
        storageScope = nextScope
        load()
    }

    func transferGuestEntriesToUserIfNeeded(userID: String) {
        let normalizedUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUserID.isEmpty else { return }

        let guestScope: StorageScope = .guest
        let userScope: StorageScope = .user(normalizedUserID)

        let guestEntries = loadEntries(for: guestScope)
        guard !guestEntries.isEmpty else { return }

        var userEntries = loadEntries(for: userScope)
        for entry in guestEntries.sorted(by: { $0.date < $1.date }) {
            mergeTransferredEntry(entry, into: &userEntries)
        }
        userEntries.sort { $0.date > $1.date }
        saveEntries(userEntries, for: userScope)
        clearStoredEntries(for: guestScope)

        if storageScope == .guest, !entries.isEmpty {
            entries = []
        }
    }

    @discardableResult
    func add(
        result: AIRecyclingResult,
        rawJSON: String,
        source: HistorySource,
        image: UIImage?,
        status: RecycleEntryStatus? = nil
    ) -> InsertResult {
        let now = Date()
        let newStatus = status ?? (result.recyclable ? .markedForRecycle : .nonRecyclable)
        if let duplicateIndex = duplicateIndex(for: result) {
            let existing = entries[duplicateIndex]
            let updatedCount = max(1, existing.scanCount) + 1
            // Always refresh duplicate details with the latest scan payload.
            let shouldUpdateDetails = true
            let localPath: String?
            if shouldUpdateDetails, let image {
                // Use a unique image path per scan so older scan previews remain browsable.
                localPath = saveImage(image, id: UUID()) ?? existing.localImagePath
            } else {
                localPath = existing.localImagePath
            }
            let updatedSource: HistorySource = (existing.source == .photo || source == .photo) ? .photo : .text
            let mergedStatus = mergedStatus(existing: existing.recycleStatus, incoming: newStatus)
            let latestScan = HistoryScan(
                date: now,
                item: result.item,
                material: result.material,
                recyclable: result.recyclable,
                bin: result.bin,
                notes: result.notes,
                disposalLocation: result.disposalLocation,
                carbonSavedKg: result.carbonSavedKg,
                rawJSON: rawJSON,
                source: source,
                localImagePath: localPath,
                remoteImagePath: existing.remoteImagePath
            )
            let mergedScans = [latestScan] + existing.scans
            let updatedEntry = HistoryEntry(
                id: existing.id,
                date: now,
                item: shouldUpdateDetails ? result.item : existing.item,
                material: shouldUpdateDetails ? result.material : existing.material,
                recyclable: shouldUpdateDetails ? result.recyclable : existing.recyclable,
                bin: shouldUpdateDetails ? result.bin : existing.bin,
                notes: shouldUpdateDetails ? result.notes : existing.notes,
                disposalLocation: shouldUpdateDetails ? result.disposalLocation : existing.disposalLocation,
                carbonSavedKg: shouldUpdateDetails ? result.carbonSavedKg : max(existing.carbonSavedKg, result.carbonSavedKg),
                recycleStatus: mergedStatus,
                rawJSON: shouldUpdateDetails ? rawJSON : existing.rawJSON,
                source: updatedSource,
                localImagePath: localPath,
                remoteImagePath: existing.remoteImagePath,
                scanCount: updatedCount,
                scans: mergedScans
            )
            entries.remove(at: duplicateIndex)
            entries.insert(updatedEntry, at: 0)
            return .duplicate(updatedEntry)
        }

        let id = UUID()
        let localPath = image.flatMap { saveImage($0, id: id) }
        let entry = HistoryEntry(
            id: id,
            date: now,
            item: result.item,
            material: result.material,
            recyclable: result.recyclable,
            bin: result.bin,
            notes: result.notes,
            disposalLocation: result.disposalLocation,
            carbonSavedKg: result.carbonSavedKg,
            recycleStatus: newStatus,
            rawJSON: rawJSON,
            source: source,
            localImagePath: localPath,
            remoteImagePath: nil,
            scanCount: 1,
            scans: [
                HistoryScan(
                    date: now,
                    item: result.item,
                    material: result.material,
                    recyclable: result.recyclable,
                    bin: result.bin,
                    notes: result.notes,
                    disposalLocation: result.disposalLocation,
                    carbonSavedKg: result.carbonSavedKg,
                    rawJSON: rawJSON,
                    source: source,
                    localImagePath: localPath,
                    remoteImagePath: nil
                ),
            ]
        )
        entries.insert(entry, at: 0)
        return .added(entry)
    }

    func isDuplicateScan(result: AIRecyclingResult) -> Bool {
        duplicateIndex(for: result) != nil
    }

    @discardableResult
    func markAsRecycled(entryID: UUID) -> HistoryEntry? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        let existing = entries[index]
        guard existing.recyclable else { return nil }
        guard existing.recycleStatus != .recycled else { return existing }

        let updated = HistoryEntry(
            id: existing.id,
            date: Date(),
            item: existing.item,
            material: existing.material,
            recyclable: existing.recyclable,
            bin: existing.bin,
            notes: existing.notes,
            disposalLocation: existing.disposalLocation,
            carbonSavedKg: existing.carbonSavedKg,
            recycleStatus: .recycled,
            rawJSON: existing.rawJSON,
            source: existing.source,
            localImagePath: existing.localImagePath,
            remoteImagePath: existing.remoteImagePath,
            scanCount: existing.scanCount,
            scans: existing.scans
        )
        entries.remove(at: index)
        entries.insert(updated, at: 0)
        return updated
    }

    @discardableResult
    func deleteEntry(entryID: UUID) -> HistoryEntry? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        return entries.remove(at: index)
    }

    @discardableResult
    func deleteEntries(entryIDs: Set<UUID>) -> [HistoryEntry] {
        guard !entryIDs.isEmpty else { return [] }
        let removed = entries.filter { entryIDs.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        entries.removeAll { entryIDs.contains($0.id) }
        return removed
    }

    func updateRemoteImagePath(entryID: UUID, path: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].remoteImagePath = path
        if !entries[index].scans.isEmpty {
            entries[index].scans[0].remoteImagePath = path
        }
    }

    func mergeRemoteImpact(_ rows: [ImpactEntryRow]) {
        var merged: [String: HistoryEntry] = [:]
        for entry in entries {
            let key = "\(ImpactKey.dayKey(for: entry.date))|\(ImpactKey.itemKey(item: entry.item, material: entry.material, bin: entry.bin))"
            if let existing = merged[key] {
                merged[key] = preferredEntryForSameKey(existing, entry)
            } else {
                merged[key] = entry
            }
        }

        for row in rows {
            let parsedScannedAt = parseScannedAt(row.scannedAt)
            let date = parsedScannedAt ?? Date()
            let sourceRaw = (row.source ?? "").lowercased()
            let source: HistorySource = sourceRaw == "text" ? .text : .photo
            let scanCount = max(1, row.scanCount ?? 1)
            let remoteStatus = remoteStatus(for: row)
            let remoteCarbonKg = max(0, Double(max(0, row.points)) / 1000.0)
            let resolvedDayKey = parsedScannedAt.map { ImpactKey.dayKey(for: $0) } ?? row.dayKey
            let key = "\(resolvedDayKey)|\(row.itemKey)"

            if let existing = merged[key] {
                let shouldPreferExistingDetails = existing.source == .photo && source == .text
                let mergedSource: HistorySource = (existing.source == .photo || source == .photo) ? .photo : .text
                let mergedDate = max(existing.date, date)
                let updated = HistoryEntry(
                    id: existing.id,
                    date: mergedDate,
                    item: shouldPreferExistingDetails ? existing.item : row.item,
                    material: shouldPreferExistingDetails ? existing.material : row.material,
                    recyclable: shouldPreferExistingDetails ? existing.recyclable : row.recyclable,
                    bin: shouldPreferExistingDetails ? existing.bin : row.bin,
                    notes: shouldPreferExistingDetails ? existing.notes : row.notes,
                    disposalLocation: existing.disposalLocation,
                    carbonSavedKg: max(existing.carbonSavedKg, remoteCarbonKg),
                    recycleStatus: mergedStatus(existing: existing.recycleStatus, incoming: remoteStatus),
                    rawJSON: existing.rawJSON.isEmpty ? "{}" : existing.rawJSON,
                    source: mergedSource,
                    localImagePath: existing.localImagePath,
                    remoteImagePath: row.imagePath ?? existing.remoteImagePath,
                    scanCount: max(existing.scanCount, scanCount),
                    scans: existing.scans
                )
                merged[key] = updated
            } else if let fallbackKey = fallbackMatchedLocalKey(
                for: row,
                resolvedDayKey: resolvedDayKey,
                in: merged
            ), let existing = merged[fallbackKey] {
                let shouldPreferExistingDetails = existing.source == .photo && source == .text
                let mergedSource: HistorySource = (existing.source == .photo || source == .photo) ? .photo : .text
                let mergedDate = max(existing.date, date)
                let updated = HistoryEntry(
                    id: existing.id,
                    date: mergedDate,
                    item: shouldPreferExistingDetails ? existing.item : row.item,
                    material: shouldPreferExistingDetails ? existing.material : row.material,
                    recyclable: shouldPreferExistingDetails ? existing.recyclable : row.recyclable,
                    bin: shouldPreferExistingDetails ? existing.bin : row.bin,
                    notes: shouldPreferExistingDetails ? existing.notes : row.notes,
                    disposalLocation: existing.disposalLocation,
                    carbonSavedKg: max(existing.carbonSavedKg, remoteCarbonKg),
                    recycleStatus: mergedStatus(existing: existing.recycleStatus, incoming: remoteStatus),
                    rawJSON: existing.rawJSON.isEmpty ? "{}" : existing.rawJSON,
                    source: mergedSource,
                    localImagePath: existing.localImagePath,
                    remoteImagePath: row.imagePath ?? existing.remoteImagePath,
                    scanCount: max(existing.scanCount, scanCount),
                    scans: existing.scans
                )
                merged.removeValue(forKey: fallbackKey)
                merged[key] = updated
            } else {
                let entry = HistoryEntry(
                    id: UUID(),
                    date: date,
                    item: row.item,
                    material: row.material,
                    recyclable: row.recyclable,
                    bin: row.bin,
                    notes: row.notes,
                    disposalLocation: nil,
                    carbonSavedKg: remoteCarbonKg,
                    recycleStatus: remoteStatus,
                    rawJSON: "{}",
                    source: source,
                    localImagePath: nil,
                    remoteImagePath: row.imagePath,
                    scanCount: scanCount,
                    scans: [
                        HistoryScan(
                            date: date,
                            item: row.item,
                            material: row.material,
                            recyclable: row.recyclable,
                            bin: row.bin,
                            notes: row.notes,
                            disposalLocation: nil,
                            carbonSavedKg: remoteCarbonKg,
                            rawJSON: "{}",
                            source: source,
                            localImagePath: nil,
                            remoteImagePath: row.imagePath
                        ),
                    ]
                )
                merged[key] = entry
            }
        }

        entries = merged.values.sorted { $0.date > $1.date }
    }

    private func fallbackMatchedLocalKey(
        for row: ImpactEntryRow,
        resolvedDayKey: String,
        in merged: [String: HistoryEntry]
    ) -> String? {
        let rowTokens = ImpactKey.similarityTokenSet(item: row.item, material: row.material)
        let rowMaterial = ImpactKey.normalizedMaterial(row.material)

        var bestKey: String?
        var bestScore = Int.min

        for (key, entry) in merged {
            let day = ImpactKey.dayKey(for: entry.date)
            guard day == resolvedDayKey else { continue }

            let entryTokens = ImpactKey.similarityTokenSet(item: entry.item, material: entry.material)
            guard ImpactKey.areSimilarTokens(entryTokens, rowTokens) else { continue }

            let entryMaterial = ImpactKey.normalizedMaterial(entry.material)
            if rowMaterial != "unknown", entryMaterial != "unknown", rowMaterial != entryMaterial {
                let overlap = entryTokens.intersection(rowTokens).count
                // Strong item-name overlap should still dedupe even if material wording differs.
                if overlap < 2 {
                    continue
                }
            }

            var score = 0
            if entry.source == .photo { score += 20 }
            if entry.localImagePath != nil { score += 10 }
            score += max(1, entry.scanCount)
            if key.contains(row.itemKey) { score += 3 }

            if score > bestScore {
                bestScore = score
                bestKey = key
            }
        }

        return bestKey
    }

    private func preferredEntryForSameKey(_ lhs: HistoryEntry, _ rhs: HistoryEntry) -> HistoryEntry {
        let lhsStatusRank = recycleStatusRank(lhs.recycleStatus)
        let rhsStatusRank = recycleStatusRank(rhs.recycleStatus)
        if lhsStatusRank != rhsStatusRank {
            return lhsStatusRank > rhsStatusRank ? lhs : rhs
        }
        let lhsSourceRank = lhs.source == .photo ? 1 : 0
        let rhsSourceRank = rhs.source == .photo ? 1 : 0
        if lhsSourceRank != rhsSourceRank {
            return lhsSourceRank > rhsSourceRank ? lhs : rhs
        }
        let lhsHasImage = lhs.localImagePath != nil
        let rhsHasImage = rhs.localImagePath != nil
        if lhsHasImage != rhsHasImage {
            return lhsHasImage ? lhs : rhs
        }
        if lhs.scanCount != rhs.scanCount {
            return lhs.scanCount > rhs.scanCount ? lhs : rhs
        }
        if lhs.date != rhs.date {
            return lhs.date > rhs.date ? lhs : rhs
        }
        if lhs.carbonSavedKg != rhs.carbonSavedKg {
            return lhs.carbonSavedKg > rhs.carbonSavedKg ? lhs : rhs
        }
        return lhs
    }

    private func remoteStatus(for row: ImpactEntryRow) -> RecycleEntryStatus {
        if !row.recyclable {
            return .nonRecyclable
        }
        if row.points > 0 {
            return .recycled
        }
        return .markedForRecycle
    }

    private func mergedStatus(existing: RecycleEntryStatus, incoming: RecycleEntryStatus) -> RecycleEntryStatus {
        if existing == .recycled || incoming == .recycled {
            return .recycled
        }
        if existing == .markedForRecycle || incoming == .markedForRecycle {
            return .markedForRecycle
        }
        return .nonRecyclable
    }

    private func recycleStatusRank(_ status: RecycleEntryStatus) -> Int {
        switch status {
        case .recycled:
            return 3
        case .markedForRecycle:
            return 2
        case .nonRecyclable:
            return 1
        }
    }

    private func parseScannedAt(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private func load() {
        entries = loadEntries(for: storageScope)
        migrateLegacyGuestStorageIfNeeded()
    }

    private func save() {
        saveEntries(entries, for: storageScope)
    }

    private func storageURL() -> URL {
        storageURL(for: storageScope)
    }

    private func storageURL(for scope: StorageScope) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ReVive", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(storageFilename(for: scope))
    }

    private func legacyStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ReVive", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(legacyStorageFilename)
    }

    private func storageKey() -> String {
        storageKey(for: storageScope)
    }

    private func storageKey(for scope: StorageScope) -> String {
        switch scope {
        case .guest:
            return guestStorageKey
        case .user(let userID):
            return userStorageKeyPrefix + userID
        }
    }

    private func storageFilename() -> String {
        storageFilename(for: storageScope)
    }

    private func storageFilename(for scope: StorageScope) -> String {
        switch scope {
        case .guest:
            return guestStorageFilename
        case .user(let userID):
            return userStorageFilenamePrefix + sanitizedStorageIdentifier(userID) + ".json"
        }
    }

    private func sanitizedStorageIdentifier(_ value: String) -> String {
        let mapped = value.map { char -> Character in
            if char.isLetter || char.isNumber {
                return char
            }
            return "_"
        }
        let sanitized = String(mapped)
        if sanitized.isEmpty {
            return "unknown"
        }
        return String(sanitized.prefix(96))
    }

    private func loadEntries(for scope: StorageScope) -> [HistoryEntry] {
        if let data = try? Data(contentsOf: storageURL(for: scope)),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            return decoded
        }

        if let data = UserDefaults.standard.data(forKey: storageKey(for: scope)),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            return decoded
        }

        if case .guest = scope {
            if let data = UserDefaults.standard.data(forKey: legacyStorageKey),
               let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
                return decoded
            }

            let legacyURL = legacyStorageURL()
            if let data = try? Data(contentsOf: legacyURL),
               let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
                return decoded
            }
        }

        return []
    }

    private func saveEntries(_ value: [HistoryEntry], for scope: StorageScope) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: storageURL(for: scope), options: [.atomic])
        UserDefaults.standard.set(data, forKey: storageKey(for: scope))
    }

    private func clearStoredEntries(for scope: StorageScope) {
        try? FileManager.default.removeItem(at: storageURL(for: scope))
        UserDefaults.standard.removeObject(forKey: storageKey(for: scope))
        if case .guest = scope {
            UserDefaults.standard.removeObject(forKey: legacyStorageKey)
            try? FileManager.default.removeItem(at: legacyStorageURL())
        }
    }

    private func migrateLegacyGuestStorageIfNeeded() {
        guard case .guest = storageScope else { return }
        guard !entries.isEmpty else { return }

        let hasCurrentGuestData =
            (UserDefaults.standard.data(forKey: guestStorageKey) != nil) ||
            FileManager.default.fileExists(atPath: storageURL(for: .guest).path)
        if !hasCurrentGuestData {
            saveEntries(entries, for: .guest)
        }
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        try? FileManager.default.removeItem(at: legacyStorageURL())
    }

    private func mergeTransferredEntry(_ incoming: HistoryEntry, into list: inout [HistoryEntry]) {
        if let duplicateIndex = duplicateIndex(for: incoming, in: list) {
            let existing = list[duplicateIndex]
            let preferExistingDetails = existing.source == .photo && incoming.source == .text
            let mergedSource: HistorySource = (existing.source == .photo || incoming.source == .photo) ? .photo : .text
            let mergedScans = (existing.scans + incoming.scans).sorted { $0.date > $1.date }
            let merged = HistoryEntry(
                id: existing.id,
                date: max(existing.date, incoming.date),
                item: preferExistingDetails ? existing.item : incoming.item,
                material: preferExistingDetails ? existing.material : incoming.material,
                recyclable: preferExistingDetails ? existing.recyclable : incoming.recyclable,
                bin: preferExistingDetails ? existing.bin : incoming.bin,
                notes: preferExistingDetails ? existing.notes : incoming.notes,
                disposalLocation: preferExistingDetails ? existing.disposalLocation : incoming.disposalLocation,
                carbonSavedKg: max(existing.carbonSavedKg, incoming.carbonSavedKg),
                recycleStatus: mergedStatus(existing: existing.recycleStatus, incoming: incoming.recycleStatus),
                rawJSON: preferExistingDetails ? existing.rawJSON : (incoming.rawJSON.isEmpty ? existing.rawJSON : incoming.rawJSON),
                source: mergedSource,
                localImagePath: existing.localImagePath ?? incoming.localImagePath,
                remoteImagePath: existing.remoteImagePath ?? incoming.remoteImagePath,
                scanCount: max(1, existing.scanCount) + max(1, incoming.scanCount),
                scans: mergedScans
            )
            list.remove(at: duplicateIndex)
            list.insert(merged, at: 0)
            return
        }

        list.insert(incoming, at: 0)
    }

    private func duplicateIndex(for result: AIRecyclingResult) -> Int? {
        let newTokens = ImpactKey.similarityTokenSet(item: result.item, material: result.material)
        let newMaterial = ImpactKey.normalizedMaterial(result.material)

        for (index, entry) in entries.enumerated() {
            let existingTokens = ImpactKey.similarityTokenSet(item: entry.item, material: entry.material)
            guard ImpactKey.areSimilarTokens(existingTokens, newTokens) else { continue }

            let existingMaterial = ImpactKey.normalizedMaterial(entry.material)
            if existingMaterial != "unknown",
               newMaterial != "unknown",
               existingMaterial != newMaterial {
                let overlap = existingTokens.intersection(newTokens).count
                // Keep duplicates merged when item naming is clearly the same.
                if overlap < 2 {
                    continue
                }
            }
            return index
        }
        return nil
    }

    private func duplicateIndex(for candidate: HistoryEntry, in list: [HistoryEntry]) -> Int? {
        let newTokens = ImpactKey.similarityTokenSet(item: candidate.item, material: candidate.material)
        let newMaterial = ImpactKey.normalizedMaterial(candidate.material)

        for (index, entry) in list.enumerated() {
            let existingTokens = ImpactKey.similarityTokenSet(item: entry.item, material: entry.material)
            guard ImpactKey.areSimilarTokens(existingTokens, newTokens) else { continue }

            let existingMaterial = ImpactKey.normalizedMaterial(entry.material)
            if existingMaterial != "unknown",
               newMaterial != "unknown",
               existingMaterial != newMaterial {
                let overlap = existingTokens.intersection(newTokens).count
                if overlap < 2 {
                    continue
                }
            }
            return index
        }
        return nil
    }

    private func saveImage(_ image: UIImage, id: UUID) -> String? {
        // Keep local write lightweight to avoid UI hitching during add-to-bin flow.
        guard let data = image.compressedJPEGData(maxDimension: 1200, quality: 0.62) else { return nil }
        let url = imagesDirectoryURL().appendingPathComponent("\(id.uuidString).jpg")
        do {
            try data.write(to: url, options: [.atomic])
            return url.path
        } catch {
            return nil
        }
    }

    private func imagesDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("impact-images", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
}
