//
//  ChallengeProgression.swift
//  Recyclability
//

import Foundation

enum ChallengeCadence: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case seasonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily:
            return "Daily"
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        case .seasonal:
            return "Seasonal"
        }
    }
}

struct ChallengeTemplate: Identifiable {
    let cadence: ChallengeCadence
    let slug: String
    let title: String
    let detail: String
    let xpReward: Int

    var id: String {
        "\(cadence.rawValue)-\(slug)"
    }
}

struct ActiveChallenge: Identifiable {
    let template: ChallengeTemplate
    let cycleKey: String

    var id: String {
        "\(template.id)-\(cycleKey)"
    }

    var cadence: ChallengeCadence { template.cadence }
    var title: String { template.title }
    var detail: String { template.detail }
    var xpReward: Int { template.xpReward }
}

enum ChallengeProgression {
    private static let totalXPKey = "revive.challenge.total_xp"
    private static let completedChallengesKey = "revive.challenge.completed_ids"
    private static let levelXPStep = 200

    static let templates: [ChallengeTemplate] = [
        ChallengeTemplate(
            cadence: .daily,
            slug: "quick-sort",
            title: "Quick Sort",
            detail: "Scan and classify 1 household item today.",
            xpReward: 40
        ),
        ChallengeTemplate(
            cadence: .daily,
            slug: "contamination-check",
            title: "Contamination Check",
            detail: "Review notes and keep one recyclable clean before disposal.",
            xpReward: 35
        ),
        ChallengeTemplate(
            cadence: .weekly,
            slug: "three-recycled",
            title: "3-Item Week",
            detail: "Mark 3 items as recycled this week.",
            xpReward: 90
        ),
        ChallengeTemplate(
            cadence: .weekly,
            slug: "material-mix",
            title: "Material Mix",
            detail: "Recycle at least two different material types this week.",
            xpReward: 85
        ),
        ChallengeTemplate(
            cadence: .monthly,
            slug: "ten-item-run",
            title: "10-Item Run",
            detail: "Scan and process 10 items this month.",
            xpReward: 180
        ),
        ChallengeTemplate(
            cadence: .monthly,
            slug: "carbon-keeper",
            title: "Carbon Keeper",
            detail: "Reach 2.0 kg CO2e saved in a month.",
            xpReward: 210
        ),
        ChallengeTemplate(
            cadence: .seasonal,
            slug: "cleanout-season",
            title: "Seasonal Cleanout",
            detail: "Complete 20 scans during the current season.",
            xpReward: 320
        ),
        ChallengeTemplate(
            cadence: .seasonal,
            slug: "consistency-season",
            title: "Consistency Season",
            detail: "Complete at least one challenge in each month of the season.",
            xpReward: 360
        ),
    ]

    static func challenges(for cadence: ChallengeCadence, now: Date = Date()) -> [ActiveChallenge] {
        let key = cycleKey(for: cadence, now: now)
        return templates
            .filter { $0.cadence == cadence }
            .map { ActiveChallenge(template: $0, cycleKey: key) }
    }

    static func currentXP() -> Int {
        max(0, UserDefaults.standard.integer(forKey: totalXPKey))
    }

    static func completedChallengeIDs() -> Set<String> {
        let values = UserDefaults.standard.stringArray(forKey: completedChallengesKey) ?? []
        return Set(values)
    }

    static func level(for xp: Int) -> Int {
        max(1, (max(0, xp) / levelXPStep) + 1)
    }

    static func levelProgress(for xp: Int) -> (level: Int, current: Int, target: Int) {
        let safeXP = max(0, xp)
        let level = level(for: safeXP)
        let base = (level - 1) * levelXPStep
        return (level: level, current: safeXP - base, target: levelXPStep)
    }

    static func isEligible(_ challenge: ActiveChallenge, entries: [HistoryEntry], now: Date = Date()) -> Bool {
        eligibility(for: challenge, entries: entries, now: now).isComplete
    }

    static func progressText(for challenge: ActiveChallenge, entries: [HistoryEntry], now: Date = Date()) -> String {
        eligibility(for: challenge, entries: entries, now: now).progressText
    }

    @discardableResult
    static func complete(_ challenge: ActiveChallenge, entries: [HistoryEntry], now: Date = Date()) -> Bool {
        guard isEligible(challenge, entries: entries, now: now) else { return false }
        var completed = completedChallengeIDs()
        guard !completed.contains(challenge.id) else { return false }
        completed.insert(challenge.id)

        let newXP = currentXP() + max(0, challenge.xpReward)
        UserDefaults.standard.set(newXP, forKey: totalXPKey)
        UserDefaults.standard.set(Array(completed), forKey: completedChallengesKey)
        NotificationCenter.default.post(name: .reviveChallengeProgressUpdated, object: nil)
        return true
    }

    private static func eligibility(
        for challenge: ActiveChallenge,
        entries: [HistoryEntry],
        now: Date
    ) -> (isComplete: Bool, progressText: String) {
        let calendar = Calendar.current
        switch challenge.template.slug {
        case "quick-sort":
            let dayInterval = calendar.dateInterval(of: .day, for: now)
            let count = countEntries(in: dayInterval, from: entries)
            return completionState(current: Double(count), target: 1, unit: .count("scan"))
        case "contamination-check":
            let dayInterval = calendar.dateInterval(of: .day, for: now)
            let count = countEntries(
                in: dayInterval,
                from: entries
            ) { entry in
                entry.recyclable && !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return completionState(current: Double(count), target: 1, unit: .count("review"))
        case "three-recycled":
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            let count = countEntries(
                in: weekInterval,
                from: entries
            ) { entry in
                entry.recycleStatus == .recycled
            }
            return completionState(current: Double(count), target: 3, unit: .count("recycled"))
        case "material-mix":
            let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
            let filtered = entriesInInterval(weekInterval, from: entries).filter { $0.recycleStatus == .recycled }
            let materialSet = Set(filtered.map { normalizedMaterial($0.material) }.filter { !$0.isEmpty })
            return completionState(current: Double(materialSet.count), target: 2, unit: .count("materials"))
        case "ten-item-run":
            let monthInterval = calendar.dateInterval(of: .month, for: now)
            let count = countEntries(in: monthInterval, from: entries)
            return completionState(current: Double(count), target: 10, unit: .count("scans"))
        case "carbon-keeper":
            let monthInterval = calendar.dateInterval(of: .month, for: now)
            let carbon = entriesInInterval(monthInterval, from: entries)
                .filter { $0.recycleStatus == .recycled }
                .reduce(0.0) { partial, entry in
                    partial + max(0, entry.carbonSavedKg)
                }
            return completionState(current: carbon, target: 2.0, unit: .carbon)
        case "cleanout-season":
            let quarterInterval = quarterDateInterval(for: now, calendar: calendar)
            let count = countEntries(in: quarterInterval, from: entries)
            return completionState(current: Double(count), target: 20, unit: .count("scans"))
        case "consistency-season":
            let quarterInterval = quarterDateInterval(for: now, calendar: calendar)
            let quarterMonths = monthsInQuarter(containing: now, calendar: calendar)
            let monthKeysWithEntries = Set(
                entriesInInterval(quarterInterval, from: entries)
                    .map { monthKey(for: $0.date, calendar: calendar) }
            )
            let coveredMonths = quarterMonths
                .map { monthKey(for: $0, calendar: calendar) }
                .filter { monthKeysWithEntries.contains($0) }
                .count
            return completionState(current: Double(coveredMonths), target: 3, unit: .count("months"))
        default:
            return completionState(current: 0, target: 1, unit: .count("progress"))
        }
    }

    private enum ProgressUnit {
        case count(String)
        case carbon
    }

    private static func completionState(
        current: Double,
        target: Double,
        unit: ProgressUnit
    ) -> (isComplete: Bool, progressText: String) {
        let safeCurrent = max(0, current)
        let safeTarget = max(1, target)
        let isComplete = safeCurrent >= safeTarget
        switch unit {
        case .count(let label):
            let currentValue = Int(floor(safeCurrent))
            let targetValue = Int(floor(safeTarget))
            return (isComplete, "\(min(currentValue, targetValue))/\(targetValue) \(label)")
        case .carbon:
            return (
                isComplete,
                "\(formatCarbon(min(safeCurrent, safeTarget)))/\(formatCarbon(safeTarget)) kg CO2e"
            )
        }
    }

    private static func entriesInInterval(_ interval: DateInterval?, from entries: [HistoryEntry]) -> [HistoryEntry] {
        guard let interval else { return [] }
        return entries.filter { interval.contains($0.date) }
    }

    private static func countEntries(
        in interval: DateInterval?,
        from entries: [HistoryEntry],
        matching predicate: (HistoryEntry) -> Bool = { _ in true }
    ) -> Int {
        entriesInInterval(interval, from: entries).filter(predicate).count
    }

    private static func normalizedMaterial(_ material: String) -> String {
        material
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func quarterDateInterval(for date: Date, calendar: Calendar) -> DateInterval? {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        var components = DateComponents()
        components.year = year
        components.month = quarterStartMonth
        components.day = 1
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .month, value: 3, to: start)
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    private static func monthsInQuarter(containing date: Date, calendar: Calendar) -> [Date] {
        guard let interval = quarterDateInterval(for: date, calendar: calendar) else { return [] }
        return (0..<3).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: interval.start)
        }
    }

    private static func monthKey(for date: Date, calendar: Calendar) -> String {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        return String(format: "%04d-%02d", year, month)
    }

    private static func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f", clamped)
        }
        return String(format: "%.1f", clamped)
    }

    private static func cycleKey(for cadence: ChallengeCadence, now: Date) -> String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)

        switch cadence {
        case .daily:
            return String(format: "%04d-%02d-%02d", year, month, day)
        case .weekly:
            let weekYear = calendar.component(.yearForWeekOfYear, from: now)
            let week = calendar.component(.weekOfYear, from: now)
            return String(format: "%04d-W%02d", weekYear, week)
        case .monthly:
            return String(format: "%04d-%02d", year, month)
        case .seasonal:
            let quarter = ((month - 1) / 3) + 1
            return String(format: "%04d-Q%d", year, quarter)
        }
    }
}

extension Notification.Name {
    static let reviveChallengeProgressUpdated = Notification.Name("revive.challengeProgressUpdated")
}
