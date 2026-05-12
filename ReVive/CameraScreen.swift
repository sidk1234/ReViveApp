//
//  CameraScreen.swift
//  Recyclability
//

import SwiftUI
import AVFoundation
import PhotosUI
import CoreLocation
import UIKit
import StoreKit

struct LocationContext {
    let latitude: Double?
    let longitude: Double?
    let locality: String?
    let administrativeArea: String?
    let postalCode: String?
    let countryCode: String?
}

struct CameraScreen: View {
    var guestHeaderInset: CGFloat = 0
    var bottomOverlayInset: CGFloat = 0
    var hideNativeBottomControls: Bool = false
    var onTextEntryActiveChange: (Bool) -> Void = { _ in }
    var onTextResultActiveChange: (Bool) -> Void = { _ in }

    @StateObject private var camera = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var pickedItem: PhotosPickerItem?
        @State private var lastSavedJSON: String?
        @State private var isPhotoPickerPresented = false
        @State private var zipCode: String = ""
        @StateObject private var locationManager = LocationManager()
        @EnvironmentObject private var history: HistoryStore
        @EnvironmentObject private var auth: AuthStore
        @State private var notesExpanded: Bool = false
        @State private var notesNeedsReadMore: Bool = false
        @State private var notesBarWidth: CGFloat = 0
        @FocusState private var zipFieldFocused: Bool
        @State private var isTextEntryActive: Bool = false
        @State private var isTextResultActive: Bool = false
        @State private var keyboardHeight: CGFloat = 0
        @State private var isTextRequestInFlight: Bool = false
        @State private var isHidingResult: Bool = false
        @State private var showQuotaLock: Bool = false
        @State private var quotaLockRequiresUpgrade: Bool = false
        @State private var manualItemText: String = ""
        @FocusState private var manualTextFocused: Bool
        @State private var scoreNotice: String?
        @State private var isDuplicateResult: Bool = false
        @State private var lastAnalysisSource: HistorySource = .photo
        @State private var showNoItemMessage: Bool = false
        @State private var noItemOpacity: Double = 0
        @State private var isLocationEntryExpanded: Bool = true
        @State private var didRequestLocationFromZipField: Bool = false
        @State private var showRecycleToast: Bool = false
        @State private var recycleToastMessage: String = "Added to Bin"
        @State private var zoomGestureStart: CGFloat = 1.0
        @State private var isZooming: Bool = false
        @State private var showFirstRecycleTutorial: Bool = false

        @Environment(\.requestReview) private var requestReview
        @AppStorage("revive.review.lastMilestone") private var reviewLastMilestone: Int = 0

        private let bottomBarInset: CGFloat = 16
        private let statusSize: CGFloat = 150
        private let notesCollapsedLines: Int = 2
        private let notesExpandedMaxHeight: CGFloat = 120
        private let textEntryKeyboardSpacing: CGFloat = 0
        private let firstRecycleTutorialKey = "revive.tutorial.capture.firstRecycleAction"

        private var capturePanelMaxWidth: CGFloat {
            horizontalSizeClass == .regular ? 480 : 360
        }

    private var bottomControlsPadding: CGFloat {
        let extra = isTextEntryActive ? textEntryKeyboardSpacing : 0
        return bottomBarInset + bottomOverlayInset + extra
    }

    private var capturedControlsBottomPadding: CGFloat {
        bottomControlsPadding + 56
    }

    private var analysisOverlayBottomPadding: CGFloat {
        bottomControlsPadding + 52
    }

        private var zoomLabel: String {
            let value = camera.zoomFactor
            if abs(value - 1.0) < 0.05 {
                return "1x"
            }
            return String(format: "%.1fx", value)
        }
        
        private var hasOverlay: Bool {
            camera.aiIsLoading || camera.aiParsedResult != nil || camera.aiErrorText != nil
        }

        private var analysisQuotaExhausted: Bool {
            auth.isAnalysisQuotaExhausted
        }

        private let topControlsTopPadding: CGFloat = 72

        private var captureControlsDisabled: Bool {
            false
        }

        private var hasLocationAccess: Bool {
            switch locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                return true
            default:
                return false
            }
        }

        private var shouldShowLocationEntry: Bool {
            return isLocationEntryExpanded
        }

        private func updateLocationEntryVisibility() {
            if hasLocationAccess {
                if didRequestLocationFromZipField {
                    return
                }
                isLocationEntryExpanded = false
            } else {
                isLocationEntryExpanded = true
            }
        }

        private func toggleLocationEntry() {
            if hasLocationAccess {
                isLocationEntryExpanded.toggle()
            } else {
                isLocationEntryExpanded = true
            }
        if !isLocationEntryExpanded {
            zipFieldFocused = false
        }
    }

    // MARK: - AI overlay
    @ViewBuilder private var aiOverlay: some View {
        if hasOverlay {
            if camera.aiIsLoading {
                ZStack {
                    loadingStatus
                        .transition(.opacity.combined(with: .scale))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(true)
            } else {
                VStack(spacing: 16) {
                    if let err = camera.aiErrorText {
                        let closeAction = lastAnalysisSource == .text ? { clearAIResult() } : nil
                        errorCard(err, onClose: closeAction)
                    } else if let result = camera.aiParsedResult {
                        if !isHidingResult {
                            VStack(spacing: 16) {
                                resultStatus
                                    .transition(.opacity.combined(with: .scale))

                                notesBar(result.notes)
                                if let notice = scoreNotice {
                                    scoreNoticeBar(notice)
                                }
                                infoCard(result)
                                actionButtons(for: result)
                                aiResultDisclaimer
                            }
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale),
                                removal: .opacity
                            ))
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, analysisOverlayBottomPadding)
                .padding(.top, 0)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(true)
            }
        }
    }

    // Updated "No Object Found" Overlay
    // Uses full screen ZStack with high zIndex to ensure visibility
    private var noItemOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
            
            VStack(spacing: 8) {
                Text("No object found")
                    .font(AppType.title(22))
                    .foregroundStyle(.white)
                
                Text("Please try again")
                    .font(AppType.body(16))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
        }
        .opacity(noItemOpacity)
        .allowsHitTesting(true)
    }

    private var loadingStatus: some View {
        AnalysisLoadingView(reduceMotion: auth.reduceMotionEnabled)
    }

    private var resultStatus: some View {
        let recyclable = camera.aiParsedResult?.recyclable ?? false
        let color = recyclable ? Color(red: 0.18, green: 0.86, blue: 0.52) : Color(red: 0.92, green: 0.27, blue: 0.32)
        let symbol = recyclable ? "checkmark" : "xmark"
        let symbolColor: Color = colorScheme == .light ? .white : .primary

        return ZStack {
            Circle()
                .fill(color)
                .frame(width: statusSize, height: statusSize)
                .shadow(color: color.opacity(0.4), radius: 18, x: 0, y: 10)

            Image(systemName: symbol)
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(symbolColor)
        }
    }

    private func errorCard(_ message: String, onClose: (() -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(message)
                .font(AppType.body(14))
                .foregroundStyle(.primary.opacity(0.95))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = message
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .liquidGlassButton(in: RoundedRectangle(cornerRadius: 8, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy error")
            
            if let onClose {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.9))
                        .frame(width: 28, height: 28)
                        .liquidGlassButton(in: RoundedRectangle(cornerRadius: 8, style: .continuous), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close error")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: capturePanelMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func actionButtons(for result: AIRecyclingResult) -> some View {
        let isRecyclable = result.recyclable
        return VStack(spacing: 10) {
            if isRecyclable {
                if isDuplicateResult {
                    Button {
                        // Keep duplicate scans updating the existing Bin entry.
                        markResultForRecycle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                            Text("Done")
                                .font(AppType.title(16))
                        }
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(.ultraThinMaterial)
                        )
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .anchorPreference(key: CaptureRecycleActionAnchorKey.self, value: .bounds) { $0 }
                } else {
                    Button {
                        markResultForRecycle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                            Text("Mark for Recycle")
                                .font(AppType.title(16))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color.yellow)
                        )
                        .shadow(color: Color.yellow.opacity(0.65), radius: 10, x: 0, y: 6)
                    }
                    .buttonStyle(.plain)
                    .anchorPreference(key: CaptureRecycleActionAnchorKey.self, value: .bounds) { $0 }
                }
            } else {
                Button {
                    addNonRecyclableToBin()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 15, weight: .bold))
                        Text("Add to Bin")
                            .font(AppType.title(16))
                    }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color(red: 0.92, green: 0.27, blue: 0.32))
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var zoomPill: some View {
        Text(zoomLabel)
            .font(AppType.body(11))
            .foregroundStyle(.primary.opacity(0.9))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
    }

    private var recycleToast: some View {
        Text(recycleToastMessage)
            .font(AppType.title(14))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func notesBar(_ notes: String) -> some View {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = trimmed.isEmpty ? "Result" : trimmed

        let textView: AnyView = {
            if notesExpanded {
                return AnyView(
                    ScrollView(showsIndicators: false) {
                        AddressLinkText(
                            text: displayText,
                            font: AppType.body(13),
                            color: .primary.opacity(0.92)
                        )
                    }
                    .frame(maxHeight: notesExpandedMaxHeight)
                )
            }
            return AnyView(
                AddressLinkText(
                    text: displayText,
                    font: AppType.body(13),
                    color: .primary.opacity(0.92),
                    lineLimit: notesCollapsedLines
                )
            )
        }()

        return HStack(alignment: .top, spacing: 10) {
            textView

            if notesNeedsReadMore || notesExpanded {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        notesExpanded.toggle()
                    }
                } label: {
                    Text(notesExpanded ? "Read less" : "Read more...")
                        .font(AppType.body(12))
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .foregroundStyle(.primary.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                    clearAIResult()
                }
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.primary.opacity(0.85))
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .liquidGlassButton(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: capturePanelMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        notesBarWidth = proxy.size.width
                        updateNotesFit(displayText)
                    }
                    .onChange(of: proxy.size.width) { _, newValue in
                        notesBarWidth = newValue
                        updateNotesFit(displayText)
                    }
            }
        )
        .onChange(of: displayText) { _, _ in
            notesExpanded = false
            updateNotesFit(displayText)
        }
    }

    private func scoreNoticeBar(_ message: String) -> some View {
        Text(message)
            .font(AppType.body(12))
            .foregroundStyle(.primary.opacity(0.9))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: capturePanelMaxWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
            )
    }

    private func updateNotesFit(_ text: String) {
        guard notesBarWidth > 0 else { return }
        let font = UIFont(name: "Avenir Next Medium", size: 13) ?? UIFont.systemFont(ofSize: 13, weight: .medium)
        let buttonFont = UIFont(name: "Avenir Next Medium", size: 12) ?? UIFont.systemFont(ofSize: 12, weight: .medium)
        let readMoreWidth = max(
            ("Read more..." as NSString).size(withAttributes: [.font: buttonFont]).width,
            ("Read less" as NSString).size(withAttributes: [.font: buttonFont]).width
        )
        let availableWidth = max(0, notesBarWidth - (14 * 2) - 28 - 10 - readMoreWidth - 8)
        let bounding = (text as NSString).boundingRect(
            with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).size
        let maxHeight = font.lineHeight * CGFloat(notesCollapsedLines)
        let needs = bounding.height > maxHeight + 1
        if notesNeedsReadMore != needs {
            notesNeedsReadMore = needs
        }
        if !needs {
            notesExpanded = false
        }
    }

    private func infoCard(_ result: AIRecyclingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(title: "Item", value: result.item)
            infoRow(title: "Material", value: result.material)
            infoRow(title: "Recyclable", value: result.recyclable ? "Yes" : "No")
            infoRow(title: "Carbon Saved", value: formatCarbonSaved(result.carbonSavedKg))
            infoRow(title: "Bin", value: analysisBinValue(for: result))
        }
        .frame(maxWidth: capturePanelMaxWidth, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func analysisBinValue(for result: AIRecyclingResult) -> String {
        let baseBin = result.bin.trimmingCharacters(in: .whitespacesAndNewlines)
        let location = DisposalLocationFormatter.formatted(result.disposalLocation)
        guard let location else { return baseBin }
        return location
    }

    private var aiResultDisclaimer: some View {
        Text("Results are AI-generated. Please proceed with caution.")
            .font(AppType.body(11))
            .foregroundStyle(.primary.opacity(0.6))
            .multilineTextAlignment(.center)
            .frame(maxWidth: capturePanelMaxWidth)
            .padding(.top, 2)
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.6))
            AddressLinkText(
                text: value.isEmpty ? "Not available" : value,
                font: AppType.title(15),
                color: .primary.opacity(0.95)
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func formatCarbonSaved(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped == 0 {
            return "0 kg CO2e"
        }
        if clamped < 1 {
            return String(format: "%.2f kg CO2e", clamped)
        }
        return String(format: "%.1f kg CO2e", clamped)
    }

    private func setTextResultActive(_ active: Bool) {
        guard active != isTextResultActive else { return }
        isTextResultActive = active
        onTextResultActiveChange(active)
    }

    private func clearAIResult() {
        camera.aiResultText = nil
        camera.aiParsedResult = nil
        camera.aiErrorText = nil
        notesExpanded = false
        notesNeedsReadMore = false
        scoreNotice = nil
        isDuplicateResult = false
        setTextResultActive(false)
    }

    private func resetToCapture() {
        camera.glowImage = nil
        camera.fillImage = nil
        camera.isSelected = false
        camera.startSession()
        clearAIResult()
        camera.aiIsLoading = false
        camera.clearCapturedImage()
        isHidingResult = false
    }

    private func resetToCaptureVisual(clearResult: Bool = true) {
        camera.glowImage = nil
        camera.fillImage = nil
        camera.isSelected = false
        if clearResult {
            clearAIResult()
        }
        camera.aiIsLoading = false
    }

    private func animateResetToCapture() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isHidingResult = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                resetToCaptureVisual(clearResult: true)
            }
            camera.startSession()
            try? await Task.sleep(nanoseconds: 120_000_000)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                camera.clearCapturedImage()
            }
            isHidingResult = false
        }
    }

    private func markResultForRecycle() {
        completeFirstRecycleTutorialIfNeeded()
        addCurrentResultToBin(status: .markedForRecycle)
    }

    private func addNonRecyclableToBin() {
        addCurrentResultToBin(status: .nonRecyclable)
    }

    private func addCurrentResultToBin(status: RecycleEntryStatus) {
        guard let result = camera.aiParsedResult else { return }
        guard let raw = camera.aiResultText else { return }
        guard lastSavedJSON != raw else {
            triggerAddedToBinFeedback(message: "Added to Bin")
            return
        }

        let previewImage = lastAnalysisSource == .photo ? camera.previewImageForHistory() : nil
        let insertResult = history.add(
            result: result,
            rawJSON: raw,
            source: lastAnalysisSource,
            image: previewImage,
            status: status
        )

        switch insertResult {
        case .added(let entry):
            if auth.autoSyncImpactEnabled {
                auth.submitImpact(entry: entry, history: history)
            }
            if status == .markedForRecycle {
                scoreNotice = "Added to Bin. Open the Bin tab and tap the item to Mark as Recycled."
            } else {
                scoreNotice = nil
            }
        case .duplicate(let entry):
            if auth.autoSyncImpactEnabled {
                auth.submitImpact(entry: entry, history: history)
            }
            if status == .markedForRecycle {
                scoreNotice = "Thanks for recycling, you've already scanned this item."
            } else {
                scoreNotice = nil
            }
        }
        lastSavedJSON = raw
        if !auth.isSignedIn {
            auth.refreshGuestQuota()
        }
        triggerAddedToBinFeedback(message: status == .markedForRecycle ? "Marked for Recycle" : "Added to Bin")
        maybeRequestReviewAtScanMilestone()
    }

    private func triggerAddedToBinFeedback(message: String) {
        recycleToastMessage = message
        showRecycleToast = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
            isHidingResult = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showRecycleToast = false
            animateResetToCapture()
        }
    }

    private func switchCameraIfAllowed() {
        guard camera.capturedImage == nil else { return }
        guard !camera.aiIsLoading else { return }
        guard !captureControlsDisabled else { return }
        camera.switchCamera()
        if auth.enableHaptics {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func openPhotoLibraryIfAllowed() {
        guard camera.capturedImage == nil else { return }
        guard !camera.aiIsLoading else { return }
        guard !captureControlsDisabled else { return }
        guard !isTextEntryActive else { return }
        guard !showQuotaLock else { return }
        guard !hasOverlay else { return }
        isPhotoPickerPresented = true
    }

    private func handleShutterTap() {
        guard camera.capturedImage == nil else { return }
        guard !camera.aiIsLoading else { return }
        guard !captureControlsDisabled else { return }
        guard !isTextEntryActive else { return }
        guard !showQuotaLock else { return }
        guard !hasOverlay else { return }
        camera.takePhoto()
    }

    private func handleCaptureButtonHold() {
        guard camera.capturedImage == nil else { return }
        guard !camera.aiIsLoading else { return }
        guard !captureControlsDisabled else { return }
        guard !showQuotaLock else { return }
        guard !hasOverlay else { return }
        openTextEntry()
    }

    private func completeFirstRecycleTutorialIfNeeded() {
        if !UserDefaults.standard.bool(forKey: firstRecycleTutorialKey) {
            UserDefaults.standard.set(true, forKey: firstRecycleTutorialKey)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            showFirstRecycleTutorial = false
        }
    }

    private func resolveLocationContext() -> LocationContext {
        let trimmedZip = zipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let promptZip = trimmedZip.isEmpty ? nil : trimmedZip
        let context = LocationContext(
            latitude: nil,
            longitude: nil,
            locality: nil,
            administrativeArea: nil,
            postalCode: promptZip,
            countryCode: nil
        )
        return context
    }

    private func applyDefaultZipIfNeeded() {
        guard zipCode.isEmpty else { return }
        let stored = auth.defaultZipCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stored.isEmpty else { return }
        zipCode = stored
    }

    private func openTextEntry() {
        guard !isTextEntryActive else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isTextEntryActive = true
        }
        zipFieldFocused = false
        manualTextFocused = true
    }

    private func closeTextEntry() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isTextEntryActive = false
        }
        manualTextFocused = false
    }

    private func submitTextEntry() {
        let trimmed = manualItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !camera.aiIsLoading else { return }
        if analysisQuotaExhausted {
            showQuotaLockOverlay()
            return
        }
        guard auth.consumeAnalysisRequest() else {
            showQuotaLockOverlay()
            return
        }
        lastAnalysisSource = .text
        isTextRequestInFlight = true
        lastSavedJSON = nil
        let context = resolveLocationContext()
        zipFieldFocused = false
        manualTextFocused = false
        clearAIResult()
        setTextResultActive(true)
        Task { @MainActor in
            let accessToken = await auth.accessTokenForAPI()
            if let accessToken, !accessToken.isEmpty {
                camera.sendTextToOpenAI(
                    itemText: trimmed,
                    location: context,
                    accessToken: accessToken,
                    isProLocal: auth.hasUnlimitedAnalysis
                )
            } else {
                _ = await auth.fetchGuestQuota()
                camera.sendTextToOpenAI(
                    itemText: trimmed,
                    location: context,
                    accessToken: nil
                )
            }
        }
        closeTextEntry()
    }

    private func showQuotaLockOverlay() {
        closeTextEntry()
        quotaLockRequiresUpgrade = auth.isSignedIn
        withAnimation(.easeInOut(duration: 0.25)) {
            showQuotaLock = true
        }
        if !auth.isSignedIn {
            let review = requestReview
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { review() }
        }
    }

    private func maybeRequestReviewAtScanMilestone() {
        let total = history.entries.count
        let milestones = [10, 25, 50]
        for milestone in milestones {
            if total >= milestone && reviewLastMilestone < milestone {
                reviewLastMilestone = milestone
                let review = requestReview
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { review() }
                break
            }
        }
    }

    private func locationIconButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "location.fill")
                .foregroundStyle(.primary)
                .font(.system(size: 16, weight: .bold))
                .frame(width: 42, height: 42)
                .liquidGlassButton(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private var captureInstructionBar: some View {
        HStack(spacing: 6) {
            Text("Tap")
            Image(systemName: "camera.fill")
                .font(.system(size: 12, weight: .semibold))
            Text("Capture and hold to type an item.")
        }
        .font(AppType.body(13))
        .foregroundStyle(.primary.opacity(0.85))
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(instructionBorderColor, lineWidth: 1)
        )
    }

    private var instructionBorderColor: Color {
        colorScheme == .light ? Color.white.opacity(0.92) : Color.primary.opacity(0.2)
    }

    private var textEntryControl: some View {
        let trimmed = manualItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        let canSubmit = !trimmed.isEmpty && !camera.aiIsLoading

        return ZStack(alignment: .trailing) {
            HStack(spacing: 10) {
                TextField("Type an item (e.g., plastic bottle)", text: $manualItemText)
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(true)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.primary)
                    .tint(AppTheme.mint)
                    .focused($manualTextFocused)
                    .submitLabel(.search)
                    .onSubmit { submitTextEntry() }
                    .layoutPriority(1)

                Button {
                    submitTextEntry()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.primary)
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1.0 : 0.5)

                Button {
                    manualItemText = ""
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.primary.opacity(0.8))
                        .font(.system(size: 14, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, 64)
        .padding(.leading, 3)

            Button("Done") {
                closeTextEntry()
            }
            .font(AppType.body(15))
            .foregroundStyle(.primary.opacity(0.9))
            .buttonStyle(.plain)
            .padding(.trailing, 18)
        }
        .padding(.horizontal, 7)
        .frame(height: 52)
        .frame(maxWidth: capturePanelMaxWidth)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
        // Pad the bottom slightly to avoid clipping against the keyboard.
        .padding(.bottom, 4)
    }

    private var captureUtilityRow: some View {
        HStack {
            Spacer(minLength: 0)
            zoomPill
                .offset(y: -8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: capturePanelMaxWidth)
    }

    private var captureControlsRow: some View {
        Group {
            if isTextEntryActive {
                textEntryControl
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                captureUtilityRow
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isTextEntryActive)
    }

    @ViewBuilder
    private var zipControlsRow: some View {
        if #available(iOS 26.0, *) {
            let showZipDone = zipFieldFocused
            HStack(spacing: 12) {
                ZStack(alignment: .trailing) {
                    TextField("ZIP code", text: $zipCode)
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                        .tint(AppTheme.mint)
                        .focused($zipFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { zipFieldFocused = false }
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                        .padding(.leading, 16)
                        .padding(.trailing, showZipDone ? 52 : 16)
                        .frame(height: 48)

                    if showZipDone {
                        Button("Done") {
                            zipFieldFocused = false
                        }
                        .font(AppType.body(17))
                        .foregroundStyle(.primary.opacity(0.9))
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                .glassEffect(
                    .regular.tint(AppTheme.night.opacity(0.2)).interactive(),
                    in: .rect(cornerRadius: 16)
                )

                locationIconButton {
                    zipFieldFocused = false
                    didRequestLocationFromZipField = true
                    locationManager.requestLocation()
                }
            }
            .frame(maxWidth: capturePanelMaxWidth)
        } else {
            let showZipDone = zipFieldFocused
            HStack(spacing: 12) {
                ZStack(alignment: .trailing) {
                    TextField("ZIP code", text: $zipCode)
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.primary)
                        .tint(AppTheme.mint)
                        .focused($zipFieldFocused)
                        .submitLabel(.done)
                        .onSubmit { zipFieldFocused = false }
                        .frame(maxWidth: .infinity)
                        .layoutPriority(1)
                        .padding(.leading, 16)
                        .padding(.trailing, showZipDone ? 52 : 16)
                        .frame(height: 48)

                    if showZipDone {
                        Button("Done") {
                            zipFieldFocused = false
                        }
                        .font(AppType.body(17))
                        .foregroundStyle(.primary.opacity(0.9))
                        .buttonStyle(.plain)
                        .padding(.trailing, 14)
                    }
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )

                locationIconButton {
                    zipFieldFocused = false
                    didRequestLocationFromZipField = true
                    locationManager.requestLocation()
                }
            }
            .frame(maxWidth: capturePanelMaxWidth)
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        if let error = locationManager.errorMessage {
            Text(error)
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(maxWidth: capturePanelMaxWidth, alignment: .leading)
        }
    }

    private var locationEntrySection: some View {
        VStack(spacing: 6) {
            zipControlsRow
            locationStatus
        }
        .padding(.top, 0)
    }

    private var quotaOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 12) {
                Text(quotaLockRequiresUpgrade ? "Upgrade to keep recycling" : "Sign in to keep recycling")
                    .font(AppType.title(20))
                    .foregroundStyle(.white)

                Text(
                    quotaLockRequiresUpgrade
                        ? "You have used all free signed-in monthly scans. Upgrade your plan to continue analyzing items."
                        : "Guest scans are used up. Please sign in to scan more."
                )
                    .font(AppType.body(14))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)

                Button {
                    if quotaLockRequiresUpgrade {
                        NotificationCenter.default.post(name: .reviveRequestUpgrade, object: nil)
                    } else {
                        NotificationCenter.default.post(name: .reviveRequestSignIn, object: nil)
                    }
                } label: {
                    Text(quotaLockRequiresUpgrade ? "Upgrade" : "Sign in")
                        .font(AppType.title(16))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .allowsHitTesting(true)
        }
        .transition(.opacity)
    }

    private func handleCapturedCloseButtonTap() {
        guard !showQuotaLock else { return }
        if let result = camera.aiParsedResult {
            if result.recyclable {
                markResultForRecycle()
            } else {
                addNonRecyclableToBin()
            }
        } else {
            animateResetToCapture()
        }
    }

    private func requestSelectionAnalysis() {
        if analysisQuotaExhausted {
            showQuotaLockOverlay()
            return
        }
        guard auth.consumeAnalysisRequest() else {
            showQuotaLockOverlay()
            return
        }
        let context = resolveLocationContext()
        zipFieldFocused = false
        manualTextFocused = false
        lastAnalysisSource = .photo
        lastSavedJSON = nil
        Task { @MainActor in
            let accessToken = await auth.accessTokenForAPI()
            camera.sendSelectionToOpenAI(
                location: context,
                accessToken: accessToken,
                isProLocal: auth.hasUnlimitedAnalysis
            )
        }
    }

    @ViewBuilder
    private var mediaLayer: some View {
        if let image = camera.capturedImage {
            capturedImageLayer(image)
        } else {
            livePreviewLayer
        }
    }

    private func capturedImageLayer(_ image: UIImage) -> some View {
        GeometryReader { geo in
            let selectionEnabled = !hasOverlay && !captureControlsDisabled && !showQuotaLock
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                if let glow = camera.glowImage {
                    Image(uiImage: glow)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blendMode(.screen)
                        .opacity(1.0)

                    Image(uiImage: glow)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blendMode(.screen)
                        .opacity(0.55)
                }

                if camera.isSelected, let fill = camera.fillImage {
                    Image(uiImage: fill)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .blendMode(.screen)
                        .opacity(0.9)
                }
            }
            .contentShape(Rectangle())
            .allowsHitTesting(selectionEnabled)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        camera.handleTap(at: value.location, in: geo.size)
                    }
            )
        }
        .ignoresSafeArea()
    }

    private var livePreviewLayer: some View {
        let pinch = MagnificationGesture()
            .onChanged { value in
                if !isZooming {
                    isZooming = true
                    zoomGestureStart = camera.zoomFactor
                }
                let newFactor = zoomGestureStart * value
                camera.setZoomFactor(newFactor)
            }
            .onEnded { _ in
                isZooming = false
            }

        let switchSwipe = DragGesture(minimumDistance: 26)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                let horizontalIntent = abs(horizontal) > 42 && abs(horizontal) > abs(vertical) * 1.15
                let verticalIntent = abs(vertical) > 42 && abs(vertical) > abs(horizontal) * 1.15
                guard horizontalIntent || verticalIntent else { return }
                switchCameraIfAllowed()
            }

        return CameraPreview(session: camera.session)
            .gesture(pinch)
            .simultaneousGesture(switchSwipe)
            .allowsHitTesting(!captureControlsDisabled)
            .ignoresSafeArea()
    }

    private var topGradientOverlay: some View {
        VStack {
            LinearGradient(
                colors: [Color.black.opacity(0.6), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
            Spacer()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var bottomGradientOverlay: some View {
        VStack {
            Spacer()
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 240)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var cameraErrorOverlay: some View {
        if let cameraError = camera.cameraErrorText {
            VStack(spacing: 16) {
                errorCard(cameraError)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 70)
            .padding(.horizontal, 20)
            .padding(.bottom, bottomControlsPadding + 160)
        }
    }

    private var topControlsOverlay: some View {
        VStack {
            HStack {
                if camera.capturedImage != nil {
                    Button {
                        handleCapturedCloseButtonTap()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 42, height: 42)
                            .liquidGlassButton(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                } else if isTextEntryActive {
                    Button {
                        closeTextEntry()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 42, height: 42)
                            .liquidGlassButton(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .padding(.top, topControlsTopPadding + guestHeaderInset)
            .disabled(captureControlsDisabled)
            .animation(.easeInOut(duration: 0.2), value: guestHeaderInset)

            Spacer()
        }
        .ignoresSafeArea()
        .zIndex(100)
    }

    @ViewBuilder
    private var recycleToastOverlay: some View {
        if showRecycleToast {
            VStack {
                recycleToast
                Spacer()
            }
            .padding(.top, 56)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var liveCameraBottomControls: some View {
        let hideTextControls = lastAnalysisSource == .text && (isTextRequestInFlight || hasOverlay)
        if !hideTextControls {
            VStack(spacing: 12) {
                if isTextEntryActive {
                    captureControlsRow
                } else {
                    Group {
                        if #available(iOS 26.0, *) {
                            GlassEffectContainer(spacing: 18) {
                                captureControlsRow
                            }
                        } else {
                            captureControlsRow
                        }
                    }
                    if shouldShowLocationEntry {
                        locationEntrySection
                    }
                }
            }
            .padding(.bottom, bottomControlsPadding)
        }
    }

    @ViewBuilder
    private var capturedPhotoBottomControls: some View {
        let enabled = camera.isSelected
        VStack(spacing: 14) {
            if !camera.isSelected {
                Text("Tap the item to select it")
                    .font(AppType.body(15))
                    .foregroundStyle(.primary.opacity(0.8))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule().stroke(instructionBorderColor, lineWidth: 1)
                    )
                    .transition(.opacity)
            }

            if !hasOverlay {
                Button {
                    guard enabled else { return }
                    requestSelectionAnalysis()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                        Text("Analyze selection")
                            .font(AppType.title(18))
                    }
                    .foregroundStyle(AppTheme.accentGradient)
                    .frame(width: 268, height: 68)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                        interactive: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(!enabled)
                .grayscale(enabled ? 0.0 : 1.0)
                .opacity(enabled ? 1.0 : 0.55)
            } else if camera.aiErrorText != nil {
                Button {
                    requestSelectionAnalysis()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .bold))
                        Text("Retry")
                            .font(AppType.title(18))
                    }
                    .foregroundStyle(AppTheme.accentGradient)
                    .frame(width: 268, height: 68)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                        interactive: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, capturedControlsBottomPadding)
    }

    private var bottomControlsOverlay: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if camera.capturedImage == nil {
                    if !hideNativeBottomControls || isTextEntryActive {
                        liveCameraBottomControls
                            .padding(.bottom, isTextEntryActive ? keyboardHeight + 8 : proxy.safeAreaInsets.bottom)
                    }
                } else {
                    capturedPhotoBottomControls
                        .padding(.bottom, proxy.safeAreaInsets.bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .disabled(captureControlsDisabled)
    }

    private var coreContent: some View {
        ZStack {
            mediaLayer
            topGradientOverlay
            bottomGradientOverlay
            cameraErrorOverlay
            topControlsOverlay
            aiOverlay
                .allowsHitTesting(!captureControlsDisabled)
            recycleToastOverlay

            if showQuotaLock {
                quotaOverlay
            }

            bottomControlsOverlay

            // "No Object Found" overlay must be last to sit on top of everything
            if showNoItemMessage {
                noItemOverlay
                    .zIndex(2)
            }
        }
    }

    private var tutorialOverlayContent: some View {
        coreContent
            .overlayPreferenceValue(CaptureRecycleActionAnchorKey.self) { anchor in
                GeometryReader { proxy in
                    if showFirstRecycleTutorial, let anchor {
                        let targetRect = proxy[anchor]
                        TargetTutorialOverlay(
                            targetRect: targetRect,
                            title: "Mark For Recycle",
                            message: "Tap this highlighted button after a recyclable result so it moves into Bin for final confirmation.",
                            highlightStyle: .capsule(padding: 2),
                            showPressIndicator: true,
                            onTargetTap: {
                                markResultForRecycle()
                            }
                        )
                        .transition(.opacity)
                        .zIndex(500)
                    }
                }
            }
    }

    private func applyLifecycleAndAnimationModifiers<Content: View>(to content: Content) -> some View {
        content
            .onAppear {
                camera.hapticsEnabled = auth.enableHaptics
                updateLocationEntryVisibility()
                applyDefaultZipIfNeeded()
                camera.startSession()
            }
            .onDisappear {
                // Keep session warm across in-app navigation to avoid restart delay.
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: camera.aiIsLoading)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: camera.aiParsedResult)
            .animation(.easeInOut(duration: 0.25), value: showQuotaLock)
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: shouldShowLocationEntry)
    }

    private func applyLocationAndPreferenceObservers<Content: View>(to content: Content) -> some View {
        content
            .onChange(of: isTextEntryActive) { _, newValue in
                onTextEntryActiveChange(newValue)
            }
            .onChange(of: locationManager.postalCode) { _, newValue in
                handleLocationPostalCodeChange(newValue)
            }
            .onChange(of: locationManager.errorMessage) { _, newValue in
                handleLocationErrorChange(newValue)
            }
            .onChange(of: locationManager.authorizationStatus) { _, _ in
                updateLocationEntryVisibility()
                applyDefaultZipIfNeeded()
            }
            .onChange(of: zipCode) { _, newValue in
                handleZipCodeChange(newValue)
            }
            .onChange(of: auth.preferences.defaultZip) { _, _ in
                applyDefaultZipIfNeeded()
            }
            .onChange(of: auth.preferences.enableHaptics) { _, _ in
                camera.hapticsEnabled = auth.enableHaptics
            }
    }

    private func applyAnalysisAndQuotaObservers<Content: View>(to content: Content) -> some View {
        content
            .onChange(of: camera.aiIsLoading) { _, newValue in
                if newValue {
                    isTextRequestInFlight = false
                }
            }
            .onChange(of: camera.aiErrorText) { _, newValue in
                handleAIErrorChange(newValue)
            }
            .onChange(of: auth.guestQuota) { _, newValue in
                handleGuestQuotaChange(newValue)
            }
            .onChange(of: auth.isSignedIn) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showQuotaLock = false
                    }
                }
            }
            .onChange(of: auth.signedInQuotaRemaining) { _, newValue in
                guard auth.isSignedIn else { return }
                if (newValue ?? 0) > 0 || auth.hasUnlimitedAnalysis {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showQuotaLock = false
                    }
                }
            }
            .onChange(of: camera.noItemDetected) { _, newValue in
                handleNoItemDetectedChange(newValue)
            }
            .onChange(of: camera.aiParsedResult) { _, newValue in
                handleAIParsedResultChange(newValue)
            }
    }

    private func applySceneObservers<Content: View>(to content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPhotoPickerPresented, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, newItem in
                handlePickedItemChange(newItem)
            }
            .onChange(of: camera.capturedImage) { _, newValue in
                NotificationCenter.default.post(
                    name: .reviveCapturePhotoVisibilityChanged,
                    object: newValue != nil
                )
                // Defensive restart to avoid occasional black preview when returning to camera mode.
                if newValue == nil {
                    camera.startSession()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if camera.capturedImage == nil {
                        camera.startSession()
                    }
                case .background:
                    camera.stopSession()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveTriggerCaptureShutter)) { _ in
                handleShutterTap()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveTriggerCaptureTextEntry)) { _ in
                handleCaptureButtonHold()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenCaptureLibrary)) { _ in
                openPhotoLibraryIfAllowed()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveSwitchCaptureCamera)) { _ in
                switchCameraIfAllowed()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveDismissCaptureTextEntry)) { _ in
                guard isTextEntryActive else { return }
                closeTextEntry()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.easeInOut(duration: duration)) { keyboardHeight = frame.height }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { note in
                let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.easeInOut(duration: duration)) { keyboardHeight = 0 }
            }
    }

    private func handlePickedItemChange(_ newItem: PhotosPickerItem?) {
        guard let newItem else { return }
        Task {
            if let data = try? await newItem.loadTransferable(type: Data.self),
               let ui = UIImage(data: data) {
                await MainActor.run { camera.useImportedPhoto(ui) }
            }
            await MainActor.run { pickedItem = nil }
        }
    }

    private func handleLocationPostalCodeChange(_ newValue: String) {
        guard didRequestLocationFromZipField else { return }
        guard !newValue.isEmpty else { return }
        zipCode = newValue
        didRequestLocationFromZipField = false
        if hasLocationAccess {
            isLocationEntryExpanded = false
        }
    }

    private func handleLocationErrorChange(_ newValue: String?) {
        guard didRequestLocationFromZipField else { return }
        guard newValue != nil else { return }
        didRequestLocationFromZipField = false
    }

    private func handleZipCodeChange(_ newValue: String) {
        let filtered = newValue.filter { $0.isNumber }
        let trimmed = String(filtered.prefix(5))
        if trimmed != newValue {
            zipCode = trimmed
        }
        if !trimmed.isEmpty {
            locationManager.errorMessage = nil
        }
    }

    private func handleAIErrorChange(_ newValue: String?) {
        if newValue != nil {
            isTextRequestInFlight = false
        }
        if let message = newValue?.lowercased() {
            if message.contains("guest quota exceeded")
                || message.contains("quota_exceeded")
                || message.contains("guest access unavailable")
                || message.contains("quota exceeded") {
                showQuotaLockOverlay()
            }
        }
    }

    private func handleGuestQuotaChange(_ newValue: GuestQuota?) {
        guard !auth.isSignedIn else { return }
        if let newValue, newValue.remaining > 0 {
            withAnimation(.easeInOut(duration: 0.25)) {
                showQuotaLock = false
            }
        } else if newValue == nil {
            withAnimation(.easeInOut(duration: 0.25)) {
                showQuotaLock = false
            }
        }
    }

    private func handleNoItemDetectedChange(_ newValue: Bool) {
        guard newValue else { return }
        clearAIResult()
        camera.aiIsLoading = false
        showNoItemMessage = true

        withAnimation(.easeOut(duration: 0.2)) {
            noItemOpacity = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeIn(duration: 0.5)) {
                noItemOpacity = 0.0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showNoItemMessage = false
                camera.noItemDetected = false
            }
        }
    }

    private func handleAIParsedResultChange(_ newValue: AIRecyclingResult?) {
        if newValue != nil {
            isHidingResult = false
            isTextRequestInFlight = false
        }
        if let result = newValue {
            let duplicate = history.isDuplicateScan(result: result)
            let recyclableDuplicate = duplicate && result.recyclable
            isDuplicateResult = recyclableDuplicate
            if recyclableDuplicate {
                scoreNotice = "Thanks for recycling, you've already scanned this item."
            } else {
                scoreNotice = nil
            }
            let hasSeenFirstRecycleTutorial = UserDefaults.standard.bool(forKey: firstRecycleTutorialKey)
            if result.recyclable, !hasSeenFirstRecycleTutorial {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFirstRecycleTutorial = true
                }
            } else {
                showFirstRecycleTutorial = false
            }
        } else {
            isDuplicateResult = false
            scoreNotice = nil
            showFirstRecycleTutorial = false
        }
    }

    var body: some View {
        applySceneObservers(
            to: applyAnalysisAndQuotaObservers(
                to: applyLocationAndPreferenceObservers(
                    to: applyLifecycleAndAnimationModifiers(
                        to: tutorialOverlayContent
                    )
                )
            )
        )
    }
}

private struct CaptureRecycleActionAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct AnalysisLoadingView: View {
    let reduceMotion: Bool
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var tipIndex = 0
    @State private var progressIndex = 0
    @State private var glowPulse = false
    @State private var tipTask: Task<Void, Never>?
    @State private var progressTask: Task<Void, Never>?

    private let logoText = "ReVive"
    private let tips = [
        "Rinse containers before recycling.",
        "Flatten cardboard to save space.",
        "Small plastics often can't be recycled."
    ]
    private let progressStates = [
        "Detecting",
        "Classifying",
        "Checking local rules",
    ]

    private var backgroundMotionEnabled: Bool {
        !reduceMotion && !lowPowerMode
    }

    private var textMotionEnabled: Bool {
        !reduceMotion
    }

    var body: some View {
        TimelineView(.animation) { context in
            loadingCard(time: context.date.timeIntervalSinceReferenceDate)
        }
        .onAppear {
            glowPulse = true
            startTipRotation()
            startProgressRotation()
        }
        .onDisappear {
            tipTask?.cancel()
            tipTask = nil
            progressTask?.cancel()
            progressTask = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name.NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private func loadingCard(time: TimeInterval) -> some View {
        VStack(spacing: 18) {
            loadingLogo(time: time)
            loadingTitle
            loadingProgressText
            loadingTipText
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func loadingLogo(time: TimeInterval) -> some View {
        ZStack {
            if backgroundMotionEnabled {
                floatingBackdrop(time: time)
                    .transition(.opacity)
            }

            Circle()
                .fill(AppTheme.mint.opacity(0.08))
                .frame(width: 168, height: 168)
                .overlay(
                    Circle()
                        .stroke(AppTheme.mint.opacity(0.35), lineWidth: 10)
                )
                .shadow(color: AppTheme.mint.opacity(glowPulse ? 0.6 : 0.35), radius: glowPulse ? 24 : 14, x: 0, y: 0)
                .animation(
                    backgroundMotionEnabled ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true) : .default,
                    value: glowPulse
                )

            HStack(spacing: 1) {
                ForEach(Array(logoText.enumerated()), id: \.offset) { index, character in
                    let lift = textMotionEnabled
                        ? max(0, sin((time * 4.8) - (Double(index) * 0.75)) * 8)
                        : 0
                    Text(String(character))
                        .font(AppType.title(24))
                        .foregroundStyle(.primary.opacity(0.93))
                        .offset(y: CGFloat(-lift))
                }
            }
        }
    }

    private var loadingTitle: some View {
        Text("Analyzing your item...")
            .font(AppType.title(17))
            .foregroundStyle(.primary.opacity(0.92))
    }

    private var loadingProgressText: some View {
        Text(progressStates[progressIndex])
            .font(AppType.title(14))
            .foregroundStyle(AppTheme.mint.opacity(0.95))
            .id(progressIndex)
            .transition(.opacity)
    }

    private var loadingTipText: some View {
        Text(tips[tipIndex])
            .font(AppType.body(12))
            .foregroundStyle(.primary.opacity(0.62))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 280)
            .id(tipIndex)
            .transition(.opacity)
    }

    @ViewBuilder
    private func floatingBackdrop(time: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let baseX = cos(Double(index) * 0.78) * 92
                let baseY = sin(Double(index) * 0.62) * 74
                let driftX = sin(time * 0.8 + Double(index)) * 16
                let driftY = cos(time * 0.6 + Double(index) * 0.9) * 12
                Circle()
                    .fill(AppTheme.mint.opacity(0.18))
                    .frame(width: CGFloat(6 + (index % 3) * 4), height: CGFloat(6 + (index % 3) * 4))
                    .offset(x: CGFloat(baseX + driftX), y: CGFloat(baseY + driftY))
            }
        }
    }

    private func startTipRotation() {
        tipTask?.cancel()
        tipTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.25)) {
                    tipIndex = (tipIndex + 1) % tips.count
                }
            }
        }
    }

    private func startProgressRotation() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled {
                for phase in 0..<progressStates.count {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        progressIndex = phase
                    }
                    try? await Task.sleep(nanoseconds: 1_050_000_000)
                    guard !Task.isCancelled else { return }
                }
            }
        }
    }
}

// MARK: - Config loader (production keys must come from Supabase Edge Functions)
enum Secrets {
    static func value(for key: String) -> String {
        // Keys are fetched from Supabase Edge Functions and cached locally.
        guard let config = AppConfigCache.load() else { return "" }
        switch key {
        case "SUPABASE_URL":
            return config.supabaseURL
        case "SUPABASE_ANON_KEY":
            return config.supabaseAnonKey
        case "GOOGLE_IOS_CLIENT_ID":
            return config.googleIOSClientID
        case "GOOGLE_WEB_CLIENT_ID":
            return config.googleWebClientID
        case "GOOGLE_REVERSED_CLIENT_ID":
            return config.googleReversedClientID
        default:
            return ""
        }
    }
}
