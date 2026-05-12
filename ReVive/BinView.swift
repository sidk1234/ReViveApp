import SwiftUI
import UIKit
import ImageIO

struct BinView: View {
    private struct PendingSwipeAction: Identifiable {
        enum Kind {
            case mark
            case delete
        }

        let id = UUID()
        let entryID: UUID
        let kind: Kind
    }

    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedEntry: HistoryEntry?
    @State private var isSelectionMode: Bool = false
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var showBulkRecycleConfirm: Bool = false
    @State private var showBulkDeleteConfirm: Bool = false
    @State private var pendingSwipeAction: PendingSwipeAction?
    @State private var showConfetti: Bool = false
    @State private var showCarbonSavedOverlay: Bool = false
    @State private var carbonSavedOverlayText: String = ""
    @State private var searchText: String = ""
    @State private var showMarkAsRecycledTutorial: Bool = false
    @AppStorage("revive.tutorial.mainTabs.overlayVisible") private var isMainTutorialOverlayActive = false

    private let markAsRecycledTutorialKey = "revive.tutorial.bin.markAsRecycled"

    private var totalCount: Int {
        history.entries.count
    }

    private var markedCount: Int {
        history.entries.filter { $0.recycleStatus == .markedForRecycle }.count
    }

    private var recycledCount: Int {
        history.entries.filter { $0.recycleStatus == .recycled }.count
    }

    private var totalCarbonSavedKg: Double {
        history.entries
            .filter { $0.recycleStatus == .recycled }
            .reduce(0) { partial, entry in
                partial + max(0, entry.carbonSavedKg)
            }
    }

    private var recyclablePendingEntries: [HistoryEntry] {
        history.entries.filter { $0.recyclable && $0.recycleStatus != .recycled }
    }

    private var filteredEntries: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter { entry in
            [
                entry.item,
                entry.material,
                entry.bin,
                entry.notes,
                entry.recycleStatus.rawValue
            ].joined(separator: " ").lowercased().contains(query)
        }
    }

    private var filteredMarkableCount: Int {
        filteredEntries.filter { $0.recyclable && $0.recycleStatus != .recycled }.count
    }

    private var selectedEntries: [HistoryEntry] {
        history.entries.filter { selectedEntryIDs.contains($0.id) }
    }

    private var canMarkSelectedEntries: Bool {
        !selectedEntries.isEmpty &&
        selectedEntries.allSatisfy { $0.recyclable && $0.recycleStatus != .recycled }
    }

    private var firstMarkableEntryID: UUID? {
        filteredEntries.first(where: { $0.recyclable && $0.recycleStatus != .recycled })?.id
    }

    private var firstMarkableEntry: HistoryEntry? {
        filteredEntries.first(where: { $0.recyclable && $0.recycleStatus != .recycled })
    }

    private var hasVisibleEntries: Bool {
        !history.entries.isEmpty && !filteredEntries.isEmpty
    }

    var body: some View {
        configuredView
    }

    private var configuredView: some View {
        rootView
            .sheet(item: $selectedEntry) { entry in
                detailSheet(for: entry)
            }
            .overlay {
                overlayContent
            }
            .overlayPreferenceValue(BinMarkAsRecycledAnchorKey.self) { anchor in
                markAsRecycledTutorialOverlay(anchor: anchor)
            }
            .animation(.easeInOut(duration: 0.2), value: showBulkRecycleConfirm)
            .animation(.easeInOut(duration: 0.2), value: showBulkDeleteConfirm)
            .animation(.easeInOut(duration: 0.2), value: pendingSwipeAction?.id)
            .animation(.easeInOut(duration: 0.2), value: showCarbonSavedOverlay)
            .onAppear {
                updateMarkAsRecycledTutorialVisibility()
            }
            .onChange(of: history.entries.map(\.id)) { _, ids in
                let idSet = Set(ids)
                selectedEntryIDs = selectedEntryIDs.intersection(idSet)
                if selectedEntryIDs.isEmpty, isSelectionMode, filteredMarkableCount == 0 {
                    isSelectionMode = false
                }
                prewarmBinThumbnailCache(for: filteredEntries)
                updateMarkAsRecycledTutorialVisibility()
            }
            .onChange(of: searchText) { _, _ in
                prewarmBinThumbnailCache(for: filteredEntries)
                updateMarkAsRecycledTutorialVisibility()
            }
            .onChange(of: isSelectionMode) { _, _ in
                updateMarkAsRecycledTutorialVisibility()
            }
            .onChange(of: selectedEntry?.id) { _, _ in
                updateMarkAsRecycledTutorialVisibility()
            }
            .onChange(of: isMainTutorialOverlayActive) { _, _ in
                updateMarkAsRecycledTutorialVisibility()
            }
    }

    private var rootView: some View {
        ZStack {
            backgroundView
            contentView
        }
    }

    private var backgroundView: some View {
        AppTheme.backgroundGradient(colorScheme)
            .ignoresSafeArea()
    }

    private var contentView: some View {
        GeometryReader { pageGeo in
            let horizontalPadding = AppLayout.pageHorizontalPadding(for: pageGeo.size.width)
            let topPadding = AppLayout.pageTopPadding(for: pageGeo.size.width)
            let bottomPadding = AppLayout.pageBottomPadding(for: pageGeo.size.width)

            contentList(
                pageWidth: pageGeo.size.width,
                horizontalPadding: horizontalPadding,
                topPadding: topPadding,
                bottomPadding: bottomPadding
            )
        }
    }

    private func contentList(
        pageWidth: CGFloat,
        horizontalPadding: CGFloat,
        topPadding: CGFloat,
        bottomPadding: CGFloat
    ) -> some View {
        List {
            headerSection(
                pageWidth: pageWidth,
                horizontalPadding: horizontalPadding,
                topPadding: topPadding
            )
            entryRows(horizontalPadding: horizontalPadding, bottomPadding: bottomPadding)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .onAppear {
            prewarmBinThumbnailCache(for: filteredEntries)
        }
    }

    private func headerSection(
        pageWidth: CGFloat,
        horizontalPadding: CGFloat,
        topPadding: CGFloat
    ) -> some View {
        Section {
            BinHeaderSection(
                totalCount: totalCount,
                markedCount: markedCount,
                recycledCount: recycledCount,
                totalCarbonSavedKg: totalCarbonSavedKg,
                isSelectionMode: isSelectionMode,
                hasEntries: !history.entries.isEmpty,
                filteredEntriesEmpty: filteredEntries.isEmpty,
                filteredMarkableCount: filteredMarkableCount,
                selectedEntryIDsCount: selectedEntryIDs.count,
                canMarkSelectedEntries: canMarkSelectedEntries,
                searchText: $searchText,
                onToggleSelectionMode: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        isSelectionMode.toggle()
                        if !isSelectionMode {
                            selectedEntryIDs.removeAll()
                        }
                    }
                },
                onMarkSelected: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBulkRecycleConfirm = true
                    }
                },
                onDeleteSelected: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBulkDeleteConfirm = true
                    }
                }
            )
            .padding(.top, topPadding)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptivePageFrame(width: pageWidth)
        }
        .listRowInsets(EdgeInsets(top: 0, leading: horizontalPadding, bottom: 0, trailing: horizontalPadding))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func entryRows(horizontalPadding: CGFloat, bottomPadding: CGFloat) -> some View {
        if hasVisibleEntries {
            ForEach(filteredEntries) { entry in
                BinEntryRow(
                    entry: entry,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedEntryIDs.contains(entry.id),
                    firstMarkableEntryID: firstMarkableEntryID,
                    showMarkAsRecycledTutorial: showMarkAsRecycledTutorial,
                    horizontalPadding: horizontalPadding,
                    isSelectable: entry.recyclable && entry.recycleStatus != .recycled,
                    onTap: {
                        if isSelectionMode {
                            toggleEntrySelection(entry.id)
                        } else {
                            selectedEntry = entry
                        }
                    },
                    onSwipeMark: { handleSwipeMark(entry) },
                    onSwipeDelete: { handleSwipeDelete(entry) }
                )
            }

            Color.clear
                .frame(height: bottomPadding + 10)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func detailSheet(for entry: HistoryEntry) -> some View {
        BinDetailView(
            entry: entry,
            onMarkAsRecycled: {
                completeMarkAsRecycled(entry)
            },
            onDeleteImpact: {
                deleteEntry(entry)
            }
        )
    }

    @ViewBuilder
    private var overlayContent: some View {
        ZStack {
            if showBulkRecycleConfirm {
                BinConfirmationOverlay(
                    title: "Confirm Recycling",
                    message: "Are you sure you've recycled this?",
                    cancelTitle: "No",
                    confirmTitle: "Yes",
                    confirmTint: AppTheme.mint,
                    confirmForegroundColor: .black,
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showBulkRecycleConfirm = false
                        }
                    },
                    onConfirm: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showBulkRecycleConfirm = false
                        }
                        completeMarkSelectedAsRecycled()
                    }
                )
                .transition(.opacity)
            }

            if showBulkDeleteConfirm {
                BinConfirmationOverlay(
                    title: "Delete Selected Impacts",
                    message: "This will permanently remove the selected impacts from Bin.",
                    cancelTitle: "Cancel",
                    confirmTitle: "Delete",
                    confirmTint: Color(red: 0.92, green: 0.27, blue: 0.32),
                    confirmForegroundColor: .white,
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showBulkDeleteConfirm = false
                        }
                    },
                    onConfirm: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showBulkDeleteConfirm = false
                        }
                        deleteSelectedEntries()
                    }
                )
                .transition(.opacity)
            }

            if let pendingSwipeAction {
                BinConfirmationOverlay(
                    title: pendingSwipeAction.kind == .mark ? "Confirm Mark as Recycled" : "Confirm Delete",
                    message: pendingSwipeAction.kind == .mark
                        ? "Mark this impact as recycled?"
                        : "Delete this impact from Bin?",
                    cancelTitle: "Cancel",
                    confirmTitle: pendingSwipeAction.kind == .mark ? "Mark" : "Delete",
                    confirmTint: pendingSwipeAction.kind == .mark
                        ? AppTheme.mint
                        : Color(red: 0.92, green: 0.27, blue: 0.32),
                    confirmForegroundColor: pendingSwipeAction.kind == .mark ? .black : .white,
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.pendingSwipeAction = nil
                        }
                    },
                    onConfirm: {
                        confirmPendingSwipeAction()
                    }
                )
                .transition(.opacity)
            }

            if showConfetti {
                RecycleConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if showCarbonSavedOverlay {
                VStack {
                    Text(carbonSavedOverlayText)
                        .font(AppType.title(15))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                        .liquidGlassBackground(in: Capsule())
                    Spacer()
                }
                .padding(.top, 74)
                .transition(.opacity.combined(with: .scale))
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func markAsRecycledTutorialOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { proxy in
            if showMarkAsRecycledTutorial,
               !isMainTutorialOverlayActive,
               !isSelectionMode,
               selectedEntry == nil,
               let anchor {
                let targetRect = proxy[anchor]
                TargetTutorialOverlay(
                    targetRect: targetRect,
                    title: "Mark As Recycled",
                    message: "Tap this highlighted item, then confirm that you've recycled it to move it out of pending Bin status.",
                    buttonTitle: nil,
                    onDone: nil,
                    highlightStyle: .roundedRect(cornerRadius: 20, padding: 0),
                    showDirectionalArrow: false,
                    showPressIndicator: true,
                    onTargetTap: {
                        if let entry = firstMarkableEntry {
                            selectedEntry = entry
                            completeMarkAsRecycledTutorialIfNeeded()
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(400)
            }
        }
    }

    private func handleSwipeMark(_ entry: HistoryEntry) {
        requestSwipeActionConfirm(for: entry, kind: .mark)
    }

    private func handleSwipeDelete(_ entry: HistoryEntry) {
        requestSwipeActionConfirm(for: entry, kind: .delete)
    }

    private func completeMarkAsRecycled(_ entry: HistoryEntry) {
        guard let updated = history.markAsRecycled(entryID: entry.id) else { return }
        selectedEntry = updated
        if auth.autoSyncImpactEnabled {
            auth.submitImpact(entry: updated, history: history)
        }
        let totalSaved = max(0, updated.carbonSavedKg)
        showCarbonSavedToast(totalSavedKg: totalSaved)
        triggerRecycledConfetti()
        completeMarkAsRecycledTutorialIfNeeded()
    }

    private func toggleEntrySelection(_ entryID: UUID) {
        if selectedEntryIDs.contains(entryID) {
            selectedEntryIDs.remove(entryID)
        } else {
            selectedEntryIDs.insert(entryID)
        }
    }

    private func completeMarkSelectedAsRecycled() {
        guard canMarkSelectedEntries else { return }

        var didMarkAny = false
        var totalSavedKg = 0.0
        for entryID in selectedEntryIDs {
            guard let updated = history.markAsRecycled(entryID: entryID) else { continue }
            didMarkAny = true
            totalSavedKg += max(0, updated.carbonSavedKg)
            if auth.autoSyncImpactEnabled {
                auth.submitImpact(entry: updated, history: history)
            }
        }

        selectedEntryIDs.removeAll()
        isSelectionMode = false

        if didMarkAny {
            showCarbonSavedToast(totalSavedKg: totalSavedKg)
            triggerRecycledConfetti()
            completeMarkAsRecycledTutorialIfNeeded()
        }
    }

    private func presentSwipeActionConfirm(for entry: HistoryEntry, kind: PendingSwipeAction.Kind) {
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingSwipeAction = PendingSwipeAction(entryID: entry.id, kind: kind)
        }
    }

    private func requestSwipeActionConfirm(for entry: HistoryEntry, kind: PendingSwipeAction.Kind) {
        // Defer modal presentation one runloop so List can settle swipe-action visuals first.
        DispatchQueue.main.async {
            presentSwipeActionConfirm(for: entry, kind: kind)
        }
    }

    private func confirmPendingSwipeAction() {
        guard let action = pendingSwipeAction else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            pendingSwipeAction = nil
        }

        guard let entry = history.entries.first(where: { $0.id == action.entryID }) else { return }

        switch action.kind {
        case .mark:
            guard entry.recyclable && entry.recycleStatus != .recycled else { return }
            completeMarkAsRecycled(entry)
        case .delete:
            deleteEntry(entry)
        }
    }

    private func prewarmBinThumbnailCache(for entries: [HistoryEntry]) {
        let paths = entries.compactMap(\.localImagePath).filter { !$0.isEmpty }
        guard !paths.isEmpty else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            for path in paths {
                if historyBinImageCache.object(forKey: path as NSString) != nil {
                    continue
                }
                if let image = loadDownsampledBinImage(atPath: path) ?? UIImage(contentsOfFile: path) {
                    let prepared = image.preparingForDisplay() ?? image
                    cacheHistoryBinImage(prepared, for: [path])
                }
            }
        }
    }

    private func deleteEntry(_ entry: HistoryEntry) {
        guard history.deleteEntry(entryID: entry.id) != nil else { return }
        selectedEntryIDs.remove(entry.id)
        if auth.autoSyncImpactEnabled {
            auth.deleteImpact(entry: entry)
        }
        if selectedEntry?.id == entry.id {
            selectedEntry = nil
        }
        if isSelectionMode && selectedEntryIDs.isEmpty {
            isSelectionMode = false
        }
    }

    private func deleteSelectedEntries() {
        guard !selectedEntryIDs.isEmpty else { return }

        let removed = history.deleteEntries(entryIDs: selectedEntryIDs)
        guard !removed.isEmpty else { return }

        if auth.autoSyncImpactEnabled {
            auth.deleteImpactEntries(removed)
        }

        if let selectedID = selectedEntry?.id, removed.contains(where: { $0.id == selectedID }) {
            selectedEntry = nil
        }

        selectedEntryIDs.removeAll()
        isSelectionMode = false
    }

    private func updateMarkAsRecycledTutorialVisibility() {
        let hasSeenTutorial = UserDefaults.standard.bool(forKey: markAsRecycledTutorialKey)
        let hasMarkableItem = firstMarkableEntryID != nil
        let shouldShow = !hasSeenTutorial
            && hasMarkableItem
            && !isMainTutorialOverlayActive
            && !isSelectionMode
            && selectedEntry == nil

        if shouldShow != showMarkAsRecycledTutorial {
            withAnimation(.easeInOut(duration: 0.2)) {
                showMarkAsRecycledTutorial = shouldShow
            }
        }
    }

    private func completeMarkAsRecycledTutorialIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: markAsRecycledTutorialKey) else {
            if showMarkAsRecycledTutorial {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showMarkAsRecycledTutorial = false
                }
            }
            return
        }

        UserDefaults.standard.set(true, forKey: markAsRecycledTutorialKey)
        withAnimation(.easeInOut(duration: 0.2)) {
            showMarkAsRecycledTutorial = false
        }
    }

    private func triggerRecycledConfetti() {
        showConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                showConfetti = false
            }
        }
    }

    private func showCarbonSavedToast(totalSavedKg: Double) {
        let clamped = max(0, totalSavedKg)
        carbonSavedOverlayText = "[\(formatCarbon(clamped))] carbon saved"
        withAnimation(.easeInOut(duration: 0.2)) {
            showCarbonSavedOverlay = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showCarbonSavedOverlay = false
            }
        }
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg CO2e", clamped)
        }
        return String(format: "%.1f kg CO2e", clamped)
    }
}

private struct BinEntryRow: View {
    let entry: HistoryEntry
    let isSelectionMode: Bool
    let isSelected: Bool
    let firstMarkableEntryID: UUID?
    let showMarkAsRecycledTutorial: Bool
    let horizontalPadding: CGFloat
    let isSelectable: Bool
    let onTap: () -> Void
    let onSwipeMark: () -> Void
    let onSwipeDelete: () -> Void

    var body: some View {
        BinEntryCard(
            entry: entry,
            isSelectionMode: isSelectionMode,
            isSelected: isSelected,
            onTap: onTap
        )
        .equatable()
        .anchorPreference(key: BinMarkAsRecycledAnchorKey.self, value: .bounds) { anchor in
            guard showMarkAsRecycledTutorial else { return nil }
            guard entry.id == firstMarkableEntryID else { return nil }
            return anchor
        }
        .padding(.vertical, 7)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !isSelectionMode, isSelectable {
                Button(action: onSwipeMark) {
                    Label("Mark", systemImage: "checkmark.circle.fill")
                }
                .tint(AppTheme.mint)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !isSelectionMode {
                Button(action: onSwipeDelete) {
                    Label("Delete", systemImage: "trash.fill")
                }
                .tint(Color(red: 0.92, green: 0.27, blue: 0.32))
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: horizontalPadding, bottom: 0, trailing: horizontalPadding))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

private struct BinHeaderSection: View {
    let totalCount: Int
    let markedCount: Int
    let recycledCount: Int
    let totalCarbonSavedKg: Double
    let isSelectionMode: Bool
    let hasEntries: Bool
    let filteredEntriesEmpty: Bool
    let filteredMarkableCount: Int
    let selectedEntryIDsCount: Int
    let canMarkSelectedEntries: Bool
    @Binding var searchText: String
    let onToggleSelectionMode: () -> Void
    let onMarkSelected: () -> Void
    let onDeleteSelected: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Bin")
                    .font(AppType.display(30))
                    .foregroundStyle(.primary)

                Spacer()

                if hasEntries {
                    Button(isSelectionMode ? "Done" : "Select") {
                        onToggleSelectionMode()
                    }
                    .font(AppType.title(14))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                    )
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                    .buttonStyle(.plain)
                }
            }

            BinStatsRow(
                totalCount: totalCount,
                markedCount: markedCount,
                recycledCount: recycledCount,
                totalCarbonSavedKg: totalCarbonSavedKg
            )

            BinSearchBar(text: $searchText)

            if isSelectionMode {
                BinSelectionBar(
                    selectedCount: selectedEntryIDsCount,
                    markableCount: filteredMarkableCount,
                    canMarkSelected: canMarkSelectedEntries,
                    onMarkSelected: onMarkSelected,
                    onDeleteSelected: onDeleteSelected
                )
            }

            if !hasEntries {
                VStack(spacing: 12) {
                    Image(systemName: "trash")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.7))

                    Text("Your bin is empty")
                        .font(AppType.title(18))
                        .foregroundStyle(.primary)

                    Text("Analyze an item, then tap Mark for Recycle to add it here.")
                        .font(AppType.body(14))
                        .foregroundStyle(.primary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .staticCard(cornerRadius: 22)
            } else if filteredEntriesEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.75))
                    Text("No matching items")
                        .font(AppType.title(16))
                        .foregroundStyle(.primary)
                    Text("Try a different search term.")
                        .font(AppType.body(13))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(22)
                .staticCard(cornerRadius: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BinMarkAsRecycledAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct BinConfirmationOverlay: View {
    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let confirmTint: Color
    let confirmForegroundColor: Color
    let onCancel: () -> Void
    let onConfirm: () -> Void

    init(
        title: String,
        message: String,
        cancelTitle: String,
        confirmTitle: String,
        confirmTint: Color,
        confirmForegroundColor: Color,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.cancelTitle = cancelTitle
        self.confirmTitle = confirmTitle
        self.confirmTint = confirmTint
        self.confirmForegroundColor = confirmForegroundColor
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(AppType.title(18))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(AppType.body(14))
                    .foregroundStyle(.primary.opacity(0.8))

                HStack(spacing: 10) {
                    Button(cancelTitle) {
                        onCancel()
                    }
                    .font(AppType.title(14))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )

                    Button(confirmTitle) {
                        onConfirm()
                    }
                    .font(AppType.title(14))
                    .foregroundStyle(confirmForegroundColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        tint: confirmTint
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            )
        }
    }
}

private struct BinSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.7))
            TextField("Search bin items", text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(.primary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .staticCard(cornerRadius: 16)
    }
}

private struct BinSelectionBar: View {
    let selectedCount: Int
    let markableCount: Int
    let canMarkSelected: Bool
    let onMarkSelected: () -> Void
    let onDeleteSelected: () -> Void

    private var canDeleteSelected: Bool {
        selectedCount > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(markableCount == 0
                 ? "No items are available to mark as recycled."
                 : "Select items, then mark them as recycled.")
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.75))

            HStack(spacing: 10) {
                Button {
                    onMarkSelected()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Mark (\(selectedCount))")
                            .font(AppType.title(14))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                        tint: AppTheme.mint
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canMarkSelected)
                .opacity(canMarkSelected ? 1.0 : 0.45)

                Button {
                    onDeleteSelected()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Delete (\(selectedCount))")
                            .font(AppType.title(14))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                        tint: Color(red: 0.92, green: 0.27, blue: 0.32)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!canDeleteSelected)
                .opacity(canDeleteSelected ? 1.0 : 0.45)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .stableBinGlassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BinStatsRow: View {
    let totalCount: Int
    let markedCount: Int
    let recycledCount: Int
    let totalCarbonSavedKg: Double

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 132), spacing: 10)]

        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            BinStatCard(title: "Items", value: "\(totalCount)")
            BinStatCard(title: "Marked", value: "\(markedCount)")
            BinStatCard(title: "Recycled", value: "\(recycledCount)")
            BinStatCard(title: "CO2e Saved", value: formatCarbon(totalCarbonSavedKg))
        }
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg", clamped)
        }
        return String(format: "%.1f kg", clamped)
    }
}

private struct BinStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.55))
            Text(value)
                .font(AppType.title(18))
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .stableBinGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct BinEntryCard: View, Equatable {
    @Environment(\.colorScheme) private var colorScheme
    let entry: HistoryEntry
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    private static let contentRowMinHeight: CGFloat = 96

    static func == (lhs: BinEntryCard, rhs: BinEntryCard) -> Bool {
        lhs.entry == rhs.entry &&
        lhs.isSelectionMode == rhs.isSelectionMode &&
        lhs.isSelected == rhs.isSelected
    }

    private var statusColor: Color {
        switch entry.recycleStatus {
        case .nonRecyclable:
            return Color(red: 0.92, green: 0.27, blue: 0.32)
        case .markedForRecycle:
            return Color.yellow
        case .recycled:
            return Color(red: 0.18, green: 0.86, blue: 0.52)
        }
    }

    private var statusText: String {
        switch entry.recycleStatus {
        case .nonRecyclable:
            return "Not recyclable"
        case .markedForRecycle:
            return "Marked for recycle"
        case .recycled:
            return "Recycled"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? AppTheme.mint : .primary.opacity(0.55))
                    .frame(width: 22, alignment: .center)
                    .frame(minHeight: Self.contentRowMinHeight, alignment: .center)
            }

            VStack(spacing: 8) {
                BinEntryThumbnail(entry: entry)
                Text("\(max(1, entry.scanCount))")
                    .font(AppType.title(20))
                    .foregroundStyle(colorScheme == .light ? Color.black : Color.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 64, alignment: .top)
            .frame(minHeight: Self.contentRowMinHeight, alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.item)
                        .font(AppType.title(16))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .layoutPriority(1)
                    Text(statusText)
                        .font(AppType.body(11))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.material)
                        .font(AppType.body(13))
                        .foregroundStyle(.primary.opacity(0.75))
                        .lineLimit(1)

                    Text(entry.bin)
                        .font(AppType.body(13))
                        .foregroundStyle(.primary.opacity(0.75))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(formatBinEntryDate(entry.date))
                        .font(AppType.body(11))
                        .foregroundStyle(.primary.opacity(0.6))
                    Spacer(minLength: 8)
                    Text(formatCarbon(entry.carbonSavedKg))
                        .font(AppType.body(11))
                        .foregroundStyle(statusColor.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: Self.contentRowMinHeight, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(colorScheme == .light ? Color.white.opacity(0.74) : Color.white.opacity(0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(statusColor.opacity(0.72), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg CO2e", clamped)
        }
        return String(format: "%.1f kg CO2e", clamped)
    }
}

private struct BinEntryThumbnail: View {
    let entry: HistoryEntry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 64, height: 64)

            if let image = loadHistoryImageForBin(path: entry.localImagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: entry.source == .text ? "text.alignleft" : "photo")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct BinDetailView: View {
    let entry: HistoryEntry
    let onMarkAsRecycled: () -> Void
    let onDeleteImpact: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("revive.skipRecycleConfirmation") private var skipRecycleConfirmation: Bool = false
    @State private var showConfirmCard: Bool = false
    @State private var showDeleteConfirmCard: Bool = false
    @State private var doNotShowAgain: Bool = false
    @State private var currentScanIndex: Int = 0

    private var orderedScans: [HistoryScan] {
        let scans = entry.scans.sorted { $0.date > $1.date }
        return scans.isEmpty
            ? [
                HistoryScan(
                    date: entry.date,
                    item: entry.item,
                    material: entry.material,
                    recyclable: entry.recyclable,
                    bin: entry.bin,
                    notes: entry.notes,
                    disposalLocation: entry.disposalLocation,
                    carbonSavedKg: entry.carbonSavedKg,
                    rawJSON: entry.rawJSON,
                    source: entry.source,
                    localImagePath: entry.localImagePath,
                    remoteImagePath: entry.remoteImagePath
                ),
            ]
            : scans
    }

    private var selectedScan: HistoryScan {
        let safeIndex = min(max(currentScanIndex, 0), max(0, orderedScans.count - 1))
        return orderedScans[safeIndex]
    }

    private var canMarkAsRecycled: Bool {
        entry.recyclable && entry.recycleStatus == .markedForRecycle
    }

    private var statusColor: Color {
        switch entry.recycleStatus {
        case .nonRecyclable:
            return Color(red: 0.92, green: 0.27, blue: 0.32)
        case .markedForRecycle:
            return Color.yellow
        case .recycled:
            return Color(red: 0.18, green: 0.86, blue: 0.52)
        }
    }

    private var statusText: String {
        switch entry.recycleStatus {
        case .nonRecyclable:
            return "Not recyclable"
        case .markedForRecycle:
            return "Marked for recycle"
        case .recycled:
            return "Recycled"
        }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(selectedScan.item)
                            .font(AppType.display(28))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                        if orderedScans.count > 1 {
                            HStack(spacing: 8) {
                                Button {
                                    currentScanIndex = max(0, currentScanIndex - 1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.primary.opacity(currentScanIndex > 0 ? 0.9 : 0.35))
                                        .frame(width: 28, height: 28)
                                        .liquidGlassButton(in: Circle(), interactive: currentScanIndex > 0)
                                }
                                .buttonStyle(.plain)
                                .disabled(currentScanIndex == 0)

                                Button {
                                    currentScanIndex = min(orderedScans.count - 1, currentScanIndex + 1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.primary.opacity(currentScanIndex < orderedScans.count - 1 ? 0.9 : 0.35))
                                        .frame(width: 28, height: 28)
                                        .liquidGlassButton(in: Circle(), interactive: currentScanIndex < orderedScans.count - 1)
                                }
                                .buttonStyle(.plain)
                                .disabled(currentScanIndex >= orderedScans.count - 1)
                            }
                        }
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .liquidGlassButton(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }

                    if canMarkAsRecycled {
                        Button {
                            if skipRecycleConfirmation {
                                onMarkAsRecycled()
                                dismiss()
                            } else {
                                doNotShowAgain = false
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showConfirmCard = true
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                Text("Mark as Recycled")
                                    .font(AppType.title(16))
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .liquidGlassButton(
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                                tint: AppTheme.mint
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if let image = loadHistoryImageForBin(path: selectedScan.localImagePath ?? entry.localImagePath) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                            .staticCard(cornerRadius: 22)
                    }

                    HistoryDetailInfoCard(
                        title: nil,
                        statusText: statusText,
                        statusColor: statusColor,
                        materialBinText: "\(selectedScan.material) • \(displayBinValue(for: selectedScan))",
                        notesText: selectedScan.notes,
                        carbonSavedText: formatCarbon(selectedScan.carbonSavedKg),
                        carbonSavedColor: .primary.opacity(0.8),
                        metaText: "Scan \(currentScanIndex + 1) of \(orderedScans.count) • \(max(1, entry.scanCount)) total",
                        dateText: formatBinEntryDate(selectedScan.date)
                    )

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDeleteConfirmCard = true
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Delete Impact")
                                .font(AppType.title(16))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .liquidGlassButton(
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
                            tint: Color(red: 0.92, green: 0.27, blue: 0.32)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 80)
            }

            if showConfirmCard {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Confirm Recycling")
                            .font(AppType.title(18))
                            .foregroundStyle(.primary)

                        Text("Are you sure you've recycled this?")
                            .font(AppType.body(14))
                            .foregroundStyle(.primary.opacity(0.8))

                        Button {
                            doNotShowAgain.toggle()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: doNotShowAgain ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(doNotShowAgain ? AppTheme.mint : .primary.opacity(0.7))
                                Text("Do not show again")
                                    .font(AppType.body(13))
                                    .foregroundStyle(.primary.opacity(0.85))
                            }
                        }
                        .buttonStyle(.plain)

                        HStack(spacing: 10) {
                            Button("No") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showConfirmCard = false
                                }
                            }
                            .font(AppType.title(14))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )

                            Button("Yes") {
                                if doNotShowAgain {
                                    skipRecycleConfirmation = true
                                }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showConfirmCard = false
                                }
                                onMarkAsRecycled()
                                dismiss()
                            }
                            .font(AppType.title(14))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .liquidGlassButton(
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                tint: AppTheme.mint
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 360)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )
                }
                .transition(.opacity)
            }

            if showDeleteConfirmCard {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Delete Impact")
                            .font(AppType.title(18))
                            .foregroundStyle(.primary)

                        Text("Are you sure you want to remove this impact from Bin?")
                            .font(AppType.body(14))
                            .foregroundStyle(.primary.opacity(0.8))

                        HStack(spacing: 10) {
                            Button("Cancel") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDeleteConfirmCard = false
                                }
                            }
                            .font(AppType.title(14))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )

                            Button("Delete") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDeleteConfirmCard = false
                                }
                                onDeleteImpact()
                                dismiss()
                            }
                            .font(AppType.title(14))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 11)
                            .liquidGlassButton(
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                tint: Color(red: 0.92, green: 0.27, blue: 0.32)
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 360)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.primary.opacity(0.14), lineWidth: 1)
                    )
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showConfirmCard)
        .animation(.easeInOut(duration: 0.2), value: showDeleteConfirmCard)
        .onAppear {
            currentScanIndex = 0
        }
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg CO2e", clamped)
        }
        return String(format: "%.1f kg CO2e", clamped)
    }

    private func displayBinValue(for scan: HistoryScan) -> String {
        let rawLocation = scan.disposalLocation ?? DisposalLocationFormatter.extractedFromRawPayload(scan.rawJSON)
        if let location = DisposalLocationFormatter.formatted(rawLocation) {
            return location
        }
        return scan.bin
    }
}

private struct RecycleConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = RecycleConfettiEmitterView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear

        let colors: [UIColor] = [
            UIColor(red: 0.2, green: 0.9, blue: 0.55, alpha: 1.0),
            UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),
            UIColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 1.0),
            UIColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1.0),
        ]

        view.emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.birthRate = 60
            cell.lifetime = 3.6
            cell.velocity = 320
            cell.velocityRange = 200
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 1.8
            cell.spin = 6
            cell.spinRange = 8
            cell.scale = 0.035
            cell.scaleRange = 0.06
            cell.color = color.cgColor
            cell.contents = makeConfettiImage(color: color).cgImage
            return cell
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func makeConfettiImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 16, height: 10)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor(color.cgColor)
        ctx?.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}

private final class RecycleConfettiEmitterView: UIView {
    let emitter = CAEmitterLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        emitter.emitterShape = .line
        emitter.renderMode = .additive
        layer.addSublayer(emitter)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        emitter.emitterShape = .line
        emitter.renderMode = .additive
        layer.addSublayer(emitter)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -10)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
    }
}

private let historyBinImageCache = NSCache<NSString, UIImage>()
private let binEntryDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()
private let binThumbnailMaxPixelSize: CGFloat = 240

private func cacheHistoryBinImage(_ image: UIImage, for paths: [String]) {
    for path in paths where !path.isEmpty {
        historyBinImageCache.setObject(image, forKey: path as NSString)
    }
}

private func loadDownsampledBinImage(atPath path: String) -> UIImage? {
    let fileURL = URL(fileURLWithPath: path)
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions) else {
        return nil
    }

    let downsampleOptions = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: binThumbnailMaxPixelSize
    ] as CFDictionary

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}

private func loadHistoryImageForBin(path: String?) -> UIImage? {
    guard let path, !path.isEmpty else { return nil }
    if let cached = historyBinImageCache.object(forKey: path as NSString) {
        return cached
    }

    if let image = loadDownsampledBinImage(atPath: path) ?? UIImage(contentsOfFile: path) {
        let prepared = image.preparingForDisplay() ?? image
        cacheHistoryBinImage(prepared, for: [path])
        return prepared
    }

    let fileName = URL(fileURLWithPath: path).lastPathComponent
    guard !fileName.isEmpty else { return nil }

    let fileManager = FileManager.default
    if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        let docsCandidate = docs
            .appendingPathComponent("impact-images", isDirectory: true)
            .appendingPathComponent(fileName)
        if let image = loadDownsampledBinImage(atPath: docsCandidate.path) ?? UIImage(contentsOfFile: docsCandidate.path) {
            let prepared = image.preparingForDisplay() ?? image
            cacheHistoryBinImage(prepared, for: [path, docsCandidate.path])
            return prepared
        }
    }

    if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        let supportCandidate = support
            .appendingPathComponent("ReVive", isDirectory: true)
            .appendingPathComponent("impact-images", isDirectory: true)
            .appendingPathComponent(fileName)
        if let image = loadDownsampledBinImage(atPath: supportCandidate.path) ?? UIImage(contentsOfFile: supportCandidate.path) {
            let prepared = image.preparingForDisplay() ?? image
            cacheHistoryBinImage(prepared, for: [path, supportCandidate.path])
            return prepared
        }
    }

    return nil
}

private func formatBinEntryDate(_ date: Date) -> String {
    binEntryDateFormatter.string(from: date)
}

private extension View {
    // Keep liquid glass in Bin while reducing light-mode flicker from repeated material recomposition.
    func stableBinGlassBackground<S: InsettableShape>(in shape: S) -> some View {
        self
            .liquidGlassBackground(in: shape)
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
            .compositingGroup()
    }
}

#Preview {
    BinView()
        .environmentObject(HistoryStore())
        .environmentObject(AuthStore())
}
