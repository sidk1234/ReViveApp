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

struct HistoryScan: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let item: String
    let material: String
    let recyclable: Bool
    let bin: String
    let notes: String
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
        self.carbonSavedKg = max(0, carbonSavedKg)
        self.rawJSON = rawJSON
        self.source = source
        self.localImagePath = localImagePath
        self.remoteImagePath = remoteImagePath
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

    private let storageKey = "recai.history.v1"
    private let storageFilename = "impact-history.json"

    init() {
        load()
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
        if let data = try? Data(contentsOf: storageURL()),
           let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = decoded
            return
        }

        guard let legacy = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: legacy) {
            entries = decoded
            save()
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: storageURL(), options: [.atomic])
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func storageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ReVive", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(storageFilename)
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
