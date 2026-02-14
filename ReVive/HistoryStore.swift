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

struct HistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let item: String
    let material: String
    let recyclable: Bool
    let bin: String
    let notes: String
    let rawJSON: String
    let source: HistorySource
    let localImagePath: String?
    var remoteImagePath: String?
    var scanCount: Int

    init(
        id: UUID,
        date: Date,
        item: String,
        material: String,
        recyclable: Bool,
        bin: String,
        notes: String,
        rawJSON: String,
        source: HistorySource,
        localImagePath: String?,
        remoteImagePath: String?,
        scanCount: Int
    ) {
        self.id = id
        self.date = date
        self.item = item
        self.material = material
        self.recyclable = recyclable
        self.bin = bin
        self.notes = notes
        self.rawJSON = rawJSON
        self.source = source
        self.localImagePath = localImagePath
        self.remoteImagePath = remoteImagePath
        self.scanCount = scanCount
    }

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case item
        case material
        case recyclable
        case bin
        case notes
        case rawJSON
        case source
        case localImagePath
        case remoteImagePath
        case scanCount
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
        rawJSON = try container.decode(String.self, forKey: .rawJSON)
        source = (try? container.decode(HistorySource.self, forKey: .source)) ?? .photo
        localImagePath = try? container.decode(String.self, forKey: .localImagePath)
        remoteImagePath = try? container.decode(String.self, forKey: .remoteImagePath)
        scanCount = try container.decodeIfPresent(Int.self, forKey: .scanCount) ?? 1
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
        try container.encode(rawJSON, forKey: .rawJSON)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(localImagePath, forKey: .localImagePath)
        try container.encodeIfPresent(remoteImagePath, forKey: .remoteImagePath)
        try container.encode(scanCount, forKey: .scanCount)
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
        image: UIImage?
    ) -> InsertResult {
        let now = Date()
        if let duplicateIndex = duplicateIndex(for: result) {
            let existing = entries[duplicateIndex]
            let updatedCount = max(1, existing.scanCount) + 1
            let shouldUpdateDetails = source == .photo || existing.source == .text
            let localPath: String?
            if shouldUpdateDetails, let image {
                localPath = saveImage(image, id: existing.id) ?? existing.localImagePath
            } else {
                localPath = existing.localImagePath
            }
            let updatedSource: HistorySource = (existing.source == .photo || source == .photo) ? .photo : .text
            let updatedEntry = HistoryEntry(
                id: existing.id,
                date: now,
                item: shouldUpdateDetails ? result.item : existing.item,
                material: shouldUpdateDetails ? result.material : existing.material,
                recyclable: shouldUpdateDetails ? result.recyclable : existing.recyclable,
                bin: shouldUpdateDetails ? result.bin : existing.bin,
                notes: shouldUpdateDetails ? result.notes : existing.notes,
                rawJSON: shouldUpdateDetails ? rawJSON : existing.rawJSON,
                source: updatedSource,
                localImagePath: localPath,
                remoteImagePath: existing.remoteImagePath,
                scanCount: updatedCount
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
            rawJSON: rawJSON,
            source: source,
            localImagePath: localPath,
            remoteImagePath: nil,
            scanCount: 1
        )
        entries.insert(entry, at: 0)
        return .added(entry)
    }

    func updateRemoteImagePath(entryID: UUID, path: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[index].remoteImagePath = path
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
            let existingMaterial = ImpactKey.normalizedMaterial(entry.material)
            if existingMaterial != "unknown",
               newMaterial != "unknown",
               existingMaterial != newMaterial {
                continue
            }
            let existingTokens = ImpactKey.similarityTokenSet(item: entry.item, material: entry.material)
            if ImpactKey.areSimilarTokens(existingTokens, newTokens) {
                return index
            }
        }
        return nil
    }

    private func saveImage(_ image: UIImage, id: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
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
