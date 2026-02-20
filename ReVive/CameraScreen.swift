//
//  CameraScreen.swift
//  Recyclability
//

import SwiftUI
import AVFoundation
import PhotosUI
import CoreLocation
import UIKit

struct LocationContext {
    let latitude: Double?
    let longitude: Double?
    let locality: String?
    let administrativeArea: String?
    let postalCode: String?
    let countryCode: String?
}

struct CameraScreen: View {

    @StateObject private var camera = CameraViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var pickedItem: PhotosPickerItem?
        @State private var pulse = false
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
        @State private var isTextRequestInFlight: Bool = false
        @State private var isHidingResult: Bool = false
        @State private var showQuotaLock: Bool = false
        @State private var quotaLockRequiresUpgrade: Bool = false
        @State private var manualItemText: String = ""
        @FocusState private var manualTextFocused: Bool
        @Namespace private var shutterNamespace
        @State private var scoreNotice: String?
        @State private var isDuplicateResult: Bool = false
        @State private var lastAnalysisSource: HistorySource = .photo
        @State private var showNoItemMessage: Bool = false
        @State private var noItemOpacity: Double = 0
        @State private var isLocationEntryExpanded: Bool = true
        @State private var didToggleLocationEntry: Bool = false
        @State private var showRecycleToast: Bool = false
        @State private var recycleToastMessage: String = "Added to Bin"
        @State private var zoomGestureStart: CGFloat = 1.0
        @State private var isZooming: Bool = false

        private let sideSize: CGFloat = 70
        private let shutterSize: CGFloat = 85
        private let bottomBarInset: CGFloat = 16
        private let statusSize: CGFloat = 150
        private let notesCollapsedLines: Int = 2
        private let notesExpandedMaxHeight: CGFloat = 120
        private let textEntryKeyboardSpacing: CGFloat = 0

        private var bottomControlsPadding: CGFloat {
            let extra = isTextEntryActive ? textEntryKeyboardSpacing : 0
            return bottomBarInset + extra
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

        private var guestBannerVisible: Bool {
            !auth.isSignedIn && auth.guestQuota != nil
        }

        private var topControlsTopPadding: CGFloat {
            guestBannerVisible ? 154 : 60
        }

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
            if !hasLocationAccess {
                return true
            }
            return isLocationEntryExpanded
        }

        private func updateLocationEntryVisibility() {
            if !hasLocationAccess {
                isLocationEntryExpanded = true
                didToggleLocationEntry = false
                return
            }
            if !didToggleLocationEntry {
                isLocationEntryExpanded = false
            }
        }

        private func toggleLocationEntry() {
            if hasLocationAccess {
                isLocationEntryExpanded.toggle()
                didToggleLocationEntry = true
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
                VStack {
                    Spacer()
                    loadingStatus
                        .transition(.opacity.combined(with: .scale))
                    Spacer()
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
                .padding(.bottom, 0)
                .padding(.top, 0)
                .frame(maxHeight: .infinity, alignment: .center)
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
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let angle = (time.truncatingRemainder(dividingBy: 1.1) / 1.1) * 360

            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.25), lineWidth: 10)
                    .frame(width: statusSize, height: statusSize)

                Circle()
                    .trim(from: 0.0, to: 0.25)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: statusSize, height: statusSize)
                    .rotationEffect(.degrees(angle))
            }
        }
    }

    private var resultStatus: some View {
        let recyclable = camera.aiParsedResult?.recyclable ?? false
        let color = recyclable ? Color(red: 0.18, green: 0.86, blue: 0.52) : Color(red: 0.92, green: 0.27, blue: 0.32)
        let symbol = recyclable ? "checkmark" : "xmark"

        return ZStack {
            Circle()
                .fill(color)
                .frame(width: statusSize, height: statusSize)
                .shadow(color: color.opacity(0.4), radius: 18, x: 0, y: 10)

            Image(systemName: symbol)
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.primary)
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
        .frame(maxWidth: 360, alignment: .leading)
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
        .frame(maxWidth: 360, alignment: .leading)
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
            .frame(maxWidth: 360, alignment: .leading)
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
            infoRow(title: "Bin", value: result.bin)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var aiResultDisclaimer: some View {
        Text("Results are AI-generated. Please proceed with caution.")
            .font(AppType.body(11))
            .foregroundStyle(.primary.opacity(0.6))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .padding(.top, 2)
    }

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.6))
            AddressLinkText(
                text: value.isEmpty ? "unknown" : value,
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

    private func clearAIResult() {
        camera.aiResultText = nil
        camera.aiParsedResult = nil
        camera.aiErrorText = nil
        notesExpanded = false
        notesNeedsReadMore = false
        scoreNotice = nil
        isDuplicateResult = false
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

    private func resolveLocationContext() -> LocationContext {
        let usableLocation = locationManager.usableLocation
        let hasLocation = usableLocation != nil
        let resolvedZip = locationManager.postalCode.isEmpty ? nil : locationManager.postalCode
        let manualZip = zipCode.isEmpty ? nil : zipCode
        let zipForPrompt = hasLocation ? resolvedZip : manualZip
        let context = LocationContext(
            latitude: usableLocation?.coordinate.latitude,
            longitude: usableLocation?.coordinate.longitude,
            locality: hasLocation && !locationManager.locality.isEmpty ? locationManager.locality : nil,
            administrativeArea: hasLocation && !locationManager.administrativeArea.isEmpty ? locationManager.administrativeArea : nil,
            postalCode: zipForPrompt,
            countryCode: hasLocation && !locationManager.countryCode.isEmpty ? locationManager.countryCode : nil
        )
        return context
    }

    private func applyDefaultZipIfNeeded() {
        guard !hasLocationAccess else { return }
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
        if let accessToken = auth.session?.accessToken, !accessToken.isEmpty {
            camera.sendTextToOpenAI(
                itemText: trimmed,
                location: context,
                accessToken: accessToken
            )
        } else {
            Task { @MainActor in
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
        quotaLockRequiresUpgrade = auth.isSignedIn
        withAnimation(.easeInOut(duration: 0.25)) {
            showQuotaLock = true
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

    private var locationToggleButton: some View {
        locationIconButton {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                toggleLocationEntry()
            }
            zipFieldFocused = false
            locationManager.requestLocation()
        }
    }

    private var captureInstructionBar: some View {
        Text("Tap the shutter to take a photo. Hold it to type an item.")
            .font(AppType.body(13))
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 1)
            )
    }

    private var shutterControl: some View {
        let tap = TapGesture().onEnded { camera.takePhoto() }
        let longPress = LongPressGesture(minimumDuration: 0.45).onEnded { _ in openTextEntry() }
        let gesture = longPress.exclusively(before: tap)
        let reduceMotion = auth.reduceMotionEnabled
        let scale = reduceMotion ? 1.0 : (pulse ? 1.02 : 0.98)

        return ZStack {
            Circle()
                .stroke(Color.green.opacity(0.55), lineWidth: 2)
                .frame(width: shutterSize, height: shutterSize)

            Circle()
                .stroke(.primary.opacity(0.16), lineWidth: 1)
                .frame(width: shutterSize - 10, height: shutterSize - 10)

            Image(systemName: "arrow.3.trianglepath")
                .foregroundStyle(.green)
                .font(.system(size: 28, weight: .bold))
        }
        .frame(width: shutterSize, height: shutterSize)
        .scaleEffect(scale)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)
        .liquidGlassButton(in: Circle(), tint: AppTheme.mint, interactive: true)
        .contentShape(Circle())
        .gesture(gesture)
        .matchedGeometryEffect(id: "shutterMorph", in: shutterNamespace)
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
        .frame(maxWidth: 360)
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
        .matchedGeometryEffect(id: "shutterMorph", in: shutterNamespace)
    }

    // New captureControlsRow using different layouts for Text vs Camera mode
    private var captureControlsRow: some View {
        Group {
            if isTextEntryActive {
                // TEXT MODE: Input bar matches capture instruction width, no photo button.
                textEntryControl
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                // CAMERA MODE: ZStack for perfect centering of Shutter Button
                ZStack(alignment: .center) {
                    // Layer 1: Left Button in HStack
                    HStack {
                        Button {
                            isPhotoPickerPresented = true
                        } label: {
                            Image(systemName: "photo.on.rectangle")
                                .foregroundStyle(.primary)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: sideSize, height: sideSize)
                                .liquidGlassButton(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $pickedItem, matching: .images)
                        .onChange(of: pickedItem) { _, newItem in
                            guard let newItem else { return }
                            Task {
                                if let data = try? await newItem.loadTransferable(type: Data.self),
                                   let ui = UIImage(data: data) {
                                    await MainActor.run { camera.useImportedPhoto(ui) }
                                }
                                await MainActor.run { pickedItem = nil }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)

                    // Layer 2: Center Shutter (Mathematically centered)
                    shutterControl
                }
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
                    locationManager.requestLocation()
                }
            }
            .frame(maxWidth: 360)
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
                    locationManager.requestLocation()
                }
            }
            .frame(maxWidth: 360)
        }
    }

    @ViewBuilder
    private var locationStatus: some View {
        if let error = locationManager.errorMessage {
            Text(error)
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(maxWidth: 360, alignment: .leading)
        }
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

    var body: some View {
        ZStack {

            // MARK: - Preview or captured image
            if let image = camera.capturedImage {
                GeometryReader { geo in
                    let selectionEnabled = !hasOverlay && !captureControlsDisabled && !showQuotaLock
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()

                        // Phase 1: hollow outline glow (always on)
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

                        // Phase 2: full fill when selected
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
            } else {
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

                CameraPreview(session: camera.session)
                    .gesture(pinch)
                    .allowsHitTesting(!captureControlsDisabled)
                    .ignoresSafeArea()
            }

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

            if let cameraError = camera.cameraErrorText {
                VStack(spacing: 16) {
                    errorCard(cameraError)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, 70)
                .padding(.horizontal, 20)
                .padding(.bottom, bottomBarInset + 160)
            }

            // MARK: - Top controls
            VStack {
                HStack {
                    if camera.capturedImage != nil {
                        Button {
                            guard !showQuotaLock else { return }
                            if let result = camera.aiParsedResult {
                                if result.recyclable && isDuplicateResult {
                                    markResultForRecycle()
                                } else if result.recyclable {
                                    markResultForRecycle()
                                } else {
                                    addNonRecyclableToBin()
                                }
                            } else {
                                animateResetToCapture()
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.primary)
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 42, height: 42)
                                .liquidGlassButton(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                        .offset(y: guestBannerVisible ? 8 : 0)
                    }

                    Spacer()

                    // location toggle removed; manage location in settings
                }
                .padding(.leading, 24)
                .padding(.trailing, 24)
                .padding(.top, topControlsTopPadding)
                .animation(.spring(response: 0.35, dampingFraction: 0.9), value: guestBannerVisible)
                .disabled(captureControlsDisabled)

                Spacer()
            }
            .ignoresSafeArea()
            .zIndex(100)

            // MARK: - AI overlay (always available)
            aiOverlay
                .allowsHitTesting(!captureControlsDisabled)

            if showRecycleToast {
                VStack {
                    recycleToast
                    Spacer()
                }
                .padding(.top, 56)
                .frame(maxWidth: .infinity)
            }

            if showQuotaLock {
                quotaOverlay
            }

            // MARK: - Bottom controls
            VStack {
                Spacer()

                if camera.capturedImage == nil {
                    let hideTextControls = lastAnalysisSource == .text && (isTextRequestInFlight || hasOverlay)

                    if !hideTextControls {
                        VStack(spacing: 12) {
                            if isTextEntryActive {
                                captureControlsRow
                            } else {
                                if auth.showCaptureInstructions {
                                    zoomPill
                                    captureInstructionBar
                                        .frame(maxWidth: 360)
                                } else {
                                    zoomPill
                                }
                                Group {
                                    if #available(iOS 26.0, *) {
                                        GlassEffectContainer(spacing: 18) {
                                            captureControlsRow
                                        }
                                    } else {
                                        captureControlsRow
                                    }
                                }
                            }
                        }
                        // Bottom padding adjustment for safety
                        .padding(.bottom, bottomControlsPadding)
                    }

                } else {
                    let enabled = camera.isSelected

                    VStack(spacing: 12) {
                        if !camera.isSelected {
                            Text("Tap the item to select it")
                                .font(AppType.body(14))
                                .foregroundStyle(.primary.opacity(0.8))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule().stroke(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                                .transition(.opacity)
                        }

                        if !hasOverlay {
                            Button {
                                guard enabled else { return }
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
                                let accessToken = auth.session?.accessToken
                                camera.sendSelectionToOpenAI(
                                    location: context,
                                    accessToken: accessToken
                                )

                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Analyze selection")
                                        .font(AppType.title(16))
                                }
                                .foregroundStyle(AppTheme.accentGradient)
                                .frame(width: 240, height: 60)
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
                                let accessToken = auth.session?.accessToken
                                camera.sendSelectionToOpenAI(
                                    location: context,
                                    accessToken: accessToken
                                )
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("Retry")
                                        .font(AppType.title(16))
                                }
                                .foregroundStyle(AppTheme.accentGradient)
                                .frame(width: 240, height: 60)
                                .liquidGlassButton(
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous),
                                    interactive: true
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, bottomControlsPadding)
                }
            }
            .disabled(captureControlsDisabled)
            
            // "No Object Found" overlay must be last to sit on top of everything
            if showNoItemMessage {
                noItemOverlay
                    .zIndex(2)
            }
        }
        .onAppear {
            pulse = !auth.reduceMotionEnabled
            camera.hapticsEnabled = auth.enableHaptics
            updateLocationEntryVisibility()
            applyDefaultZipIfNeeded()
            locationManager.refreshLocationIfAuthorized()
            camera.startSession()
        }
        .onDisappear {
            camera.stopSession()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: camera.aiIsLoading)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: camera.aiParsedResult)
        .animation(.easeInOut(duration: 0.25), value: showQuotaLock)
        .onChange(of: locationManager.postalCode) { _, newValue in
            guard !newValue.isEmpty else { return }
            zipCode = newValue
        }
        .onChange(of: locationManager.authorizationStatus) { _, _ in
            updateLocationEntryVisibility()
            applyDefaultZipIfNeeded()
        }
        .onChange(of: zipCode) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            let trimmed = String(filtered.prefix(5))
            if trimmed != newValue {
                zipCode = trimmed
            }
            if !trimmed.isEmpty {
                locationManager.errorMessage = nil
            }
        }
        .onChange(of: auth.preferences.defaultZip) { _, _ in
            applyDefaultZipIfNeeded()
        }
        .onChange(of: auth.preferences.enableHaptics) { _, _ in
            camera.hapticsEnabled = auth.enableHaptics
        }
        .onChange(of: auth.preferences.reduceMotion) { _, _ in
            pulse = !auth.reduceMotionEnabled
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: shouldShowLocationEntry)
        // Overlay logic - fixed animation
        .onChange(of: camera.aiIsLoading) { _, newValue in
            if newValue {
                isTextRequestInFlight = false
            }
        }
        .onChange(of: camera.aiErrorText) { _, newValue in
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
        .onChange(of: auth.guestQuota) { _, newValue in
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
            guard newValue else { return }
            clearAIResult()
            camera.aiIsLoading = false
            showNoItemMessage = true
            
            // Fade in quickly
            withAnimation(.easeOut(duration: 0.2)) {
                noItemOpacity = 1.0
            }
            
            // Fade out smoothly after brief hold
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeIn(duration: 0.5)) {
                    noItemOpacity = 0.0
                }
                
                // Cleanup after animation completes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showNoItemMessage = false
                    camera.noItemDetected = false
                }
            }
        }
        .onChange(of: camera.aiParsedResult) { _, newValue in
            if newValue != nil {
                isHidingResult = false
            }
            if newValue != nil {
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
            } else {
                isDuplicateResult = false
                scoreNotice = nil
            }
        }
        .onChange(of: camera.capturedImage) { _, newValue in
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
            case .inactive, .background:
                camera.stopSession()
            @unknown default:
                break
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
