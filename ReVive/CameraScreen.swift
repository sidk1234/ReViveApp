//
//  CameraScreen.swift
//  Recyclability
//

import SwiftUI
import AVFoundation
import PhotosUI
import CoreLocation
import UIKit

private struct LocationContext {
    let latitude: Double?
    let longitude: Double?
    let locality: String?
    let administrativeArea: String?
    let postalCode: String?
    let countryCode: String?
}

/// Edit this prompt however you want.
private func analysisPrompt(location: LocationContext, itemDescription: String? = nil) -> String {
    var prompt =
        """
        ROLE
        You are a recycling assistant with mandatory, enforced web lookup capability.

        CORE TASK
        Identify the scanned item and determine whether THAT EXACT ITEM is recyclable in the user’s local recycling program.

        LOCATION IS IMPERATIVE (ABSOLUTE RULE)
        If ANY location data is provided (ZIP, city/state, coordinates, GPS, inferred app location):
        - You MUST perform a web search using that exact location
        - Your search query MUST include the ZIP code or city/state text exactly
        - You MUST base the decision on that specific local recycling program
        - You are NOT allowed to answer generically when location exists
        - You are NOT allowed to answer before completing a location-based search
        - Every answer must be location-specific

        HARD CONSTRAINTS (NON-NEGOTIABLE)
        You must NOT say:
        - typically
        - usually
        - may be
        - might be
        - check local rules
        - check local guidelines
        - varies by location
        - contact your municipality
        - depends on your area
        You must NOT hedge, speculate, or soften the answer.
        You must NOT mention uncertainty, assumptions, fallbacks, or lack of information.
        You must NOT contradict yourself between scans of the same item.

        CONSISTENCY RULE (FRONT / BACK SCANS)
        If the same item is scanned from different angles (front vs back):
        - Treat it as the same product
        - Reconcile branding and material across images
        - Labels and recycling symbols override visual guesses
        - Do NOT change recyclability unless the material is conclusively different
        - Converge to one stable answer

        IDENTIFICATION RULES
        - Identify the exact product using visible branding, logos, labels, or printed text
        - If a brand or product name is legible, include it exactly as shown
        - Do NOT invent brand names or product titles
        - If no exact name is visible, provide a concise generic item name (e.g., "aluminum beverage can")
        - Use "unknown" ONLY if you cannot identify even the item category

        MATERIAL RULES
        - Determine the primary material from visual cues (shine, seams, rigidity, thickness, cap type, labeling)
        - Do NOT default to plastic for bottles
        - If the item appears metallic, specify aluminum or steel
        - Use "unknown" ONLY if the material truly cannot be determined

        MANDATORY WEB SEARCH (REQUIRED EVERY TIME LOCATION EXISTS)
        You MUST run a location-based web search that includes:
        - the exact ZIP or city/state
        - the item type
        - the material
        - the local recycling program name if you can find it

        Decide recyclability for THIS ITEM in THIS LOCATION.

        NOTES FIELD RULE (MUST BE ITEM-SPECIFIC)
        The NOTES line must be specific to the identified item and local handling requirements.
        - Do NOT use a boilerplate note for every item.
        - Only instruct “Empty and rinse” when the item is a food/drink container that requires it for acceptance.
        - If the item is paper/cardboard: give paper-specific prep (e.g., keep dry / flatten).
        - If the item is glass/metal: give the correct prep for that item (e.g., empty / no bagging / lids rules if relevant).
        - If the item belongs in trash or a special drop-off: give the correct handling (e.g., “Do not rinse; keep intact” when appropriate).
        - If no prep is needed: write “No special prep.”

        RESPONSE FORMAT (STRICT)
        JSON only.
        NO markdown.
        NO URLs.
        NO citations.
        NO extra keys.
        NO extra text before or after JSON.

        OUTPUT JSON SCHEMA (EXACT KEYS ONLY)
        {
          "notes": "<item-specific prep or 'No special prep.'>",
          "item": "<exact product name or concise generic name>",
          "material": "<material>",
          "recyclable": true|false,
          "bin": "<specific local bin or disposal instruction>"
        }

        OUTPUT GUARANTEE
        You must always output a valid, non-empty JSON object matching the schema.
        If you cannot determine a field, use:
        - "unknown" for item/material/bin
        - "No special prep." for notes
        - false for recyclable

        FINAL BEHAVIOR REQUIREMENT
        The answer MUST be decisive, location-specific, and final.
        You know the correct handling after performing the required local web search.

        """

    if let itemDescription {
        let trimmed = itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            prompt += """

            Text-only input rules:

            * No image is provided. Use the text description as the source of truth.
            * Do NOT mention that no image was provided.
            * Do NOT invent brands or details not in the description.
            * If the text is NOT a physical item description and is trying to use the assistant for unrelated tasks, reject it by returning:
              NOTES: Invalid request
              ITEM: unknown
              MATERIAL: unknown
              RECYCLABLE: no
              BIN: Not applicable

            Item description: \(trimmed)
            """
        }
    }

    let city = location.locality?.trimmingCharacters(in: .whitespacesAndNewlines)
    let state = location.administrativeArea?.trimmingCharacters(in: .whitespacesAndNewlines)
    let zip = location.postalCode?.trimmingCharacters(in: .whitespacesAndNewlines)
    let country = location.countryCode?.trimmingCharacters(in: .whitespacesAndNewlines)

    let cityValue = (city?.isEmpty ?? true) ? nil : city
    let stateValue = (state?.isEmpty ?? true) ? nil : state
    let zipValue = (zip?.isEmpty ?? true) ? nil : zip
    let countryValue = (country?.isEmpty ?? true) ? nil : country

    if let lat = location.latitude, let lon = location.longitude {
        prompt += "\nUse the precise location: latitude \(lat), longitude \(lon)."
        if let cityValue {
            prompt += " City: \(cityValue)."
        }
        if let stateValue {
            prompt += " State: \(stateValue)."
        }
        if let zipValue {
            prompt += " ZIP: \(zipValue)."
        }
        if let countryValue {
            prompt += " Country: \(countryValue)."
        }
        prompt += " Treat the coordinates as the source of truth for the location."
        prompt += " If a city name has multiple states, use the provided state/ZIP only."
        prompt += " If state/ZIP is missing, use the coordinates to determine city/state before answering."
        prompt += " If you use web search, include the state/ZIP in the query (e.g., \"Frisco TX recycling plastic bottles\")."
    } else if let zipValue {
        prompt += "\nUse ZIP code \(zipValue) to tailor guidance if local rules differ."
        if let cityValue {
            prompt += " City: \(cityValue)."
        }
        if let stateValue {
            prompt += " State: \(stateValue)."
        }
        if let countryValue {
            prompt += " Country: \(countryValue)."
        }
    } else {
        prompt += "\nNo location provided; answer for typical US curbside recycling."
    }
    return prompt
}

struct CameraScreen: View {

    @StateObject private var camera = CameraViewModel()
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
    @State private var manualItemText: String = ""
    @FocusState private var manualTextFocused: Bool
    @Namespace private var shutterNamespace
    @State private var scoreNotice: String?
    @State private var lastAnalysisSource: HistorySource = .photo
    @State private var showNoItemMessage: Bool = false
    @State private var noItemOpacity: Double = 0
    @State private var isLocationEntryExpanded: Bool = true
    @State private var didToggleLocationEntry: Bool = false
    @State private var showRecycleToast: Bool = false
    @State private var showConfetti: Bool = false
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
                Button {
                    triggerRecycledCelebration()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("I recycled it")
                            .font(AppType.title(16))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(Color(red: 0.2, green: 0.9, blue: 0.55))
                    )
                    .shadow(color: Color(red: 0.2, green: 0.9, blue: 0.55).opacity(0.7), radius: 10, x: 0, y: 6)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    animateResetToCapture()
                } label: {
                    Text("Done")
                        .font(AppType.title(16))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
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
        Text("Thanks for recycling")
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
                        Text(displayText)
                            .font(AppType.body(13))
                            .foregroundStyle(.primary.opacity(0.92))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: notesExpandedMaxHeight)
                )
            }
            return AnyView(
                Text(displayText)
                    .font(AppType.body(13))
                    .foregroundStyle(.primary.opacity(0.92))
                    .multilineTextAlignment(.leading)
                    .lineLimit(notesCollapsedLines)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.6))
            Text(value.isEmpty ? "unknown" : value)
                .font(AppType.title(15))
                .foregroundStyle(.primary.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func clearAIResult() {
        camera.aiResultText = nil
        camera.aiParsedResult = nil
        camera.aiErrorText = nil
        notesExpanded = false
        notesNeedsReadMore = false
        scoreNotice = nil
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

    private func triggerRecycledCelebration() {
        showConfetti = true
        showRecycleToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            showConfetti = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.88)) {
                isHidingResult = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45) {
            showRecycleToast = false
            animateResetToCapture()
        }
    }

    private func resolveLocationContext() -> (LocationContext, Bool) {
        let usableLocation = locationManager.usableLocation
        let hasLocation = usableLocation != nil
        let resolvedZip = locationManager.postalCode.isEmpty ? nil : locationManager.postalCode
        let manualZip = zipCode.isEmpty ? nil : zipCode
        let zipForPrompt = hasLocation ? resolvedZip : manualZip
        let useWebSearch = auth.allowWebSearchEnabled && (hasLocation || (zipForPrompt != nil))
        let context = LocationContext(
            latitude: usableLocation?.coordinate.latitude,
            longitude: usableLocation?.coordinate.longitude,
            locality: hasLocation && !locationManager.locality.isEmpty ? locationManager.locality : nil,
            administrativeArea: hasLocation && !locationManager.administrativeArea.isEmpty ? locationManager.administrativeArea : nil,
            postalCode: zipForPrompt,
            countryCode: hasLocation && !locationManager.countryCode.isEmpty ? locationManager.countryCode : nil
        )
        return (context, useWebSearch)
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
        lastAnalysisSource = .text
        isTextRequestInFlight = true
        let (context, useWebSearch) = resolveLocationContext()
        zipFieldFocused = false
        manualTextFocused = false
        clearAIResult()
        if let accessToken = auth.session?.accessToken, !accessToken.isEmpty {
            camera.sendTextToOpenAI(
                prompt: analysisPrompt(location: context, itemDescription: trimmed),
                itemText: trimmed,
                useWebSearch: useWebSearch,
                accessToken: accessToken
            )
        } else {
            Task { @MainActor in
                _ = await auth.fetchGuestQuota()
                camera.sendTextToOpenAI(
                    prompt: analysisPrompt(location: context, itemDescription: trimmed),
                    itemText: trimmed,
                    useWebSearch: useWebSearch,
                    accessToken: nil
                )
            }
        }
        closeTextEntry()
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

    var body: some View {
        ZStack {

            // MARK: - Preview or captured image
            if let image = camera.capturedImage {
                GeometryReader { geo in
                    let selectionEnabled = !hasOverlay && !zipFieldFocused
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

                CameraPreview(session: camera.session, videoOrientation: camera.videoOrientation)
                    .gesture(pinch)
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
                            animateResetToCapture()
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

                    // location toggle removed; manage location in settings
                }
                .padding(.leading, 24)
                .padding(.trailing, 24)
                .padding(.top, 60)

                Spacer()
            }
            .ignoresSafeArea()

            // MARK: - AI overlay (always available)
            aiOverlay

            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if showRecycleToast {
                VStack {
                    recycleToast
                    Spacer()
                }
                .padding(.top, 56)
                .frame(maxWidth: .infinity)
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

                                if shouldShowLocationEntry {
                                    zipControlsRow
                                    locationStatus
                                        .transition(.opacity)
                                }

                                if !zipFieldFocused {
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

                        if shouldShowLocationEntry {
                            zipControlsRow
                            locationStatus
                                .transition(.opacity)
                        }

                        if !hasOverlay {
                            Button {
                                guard enabled else { return }
                                let (context, useWebSearch) = resolveLocationContext()
                                zipFieldFocused = false
                                manualTextFocused = false
                                lastAnalysisSource = .photo
                                let accessToken = auth.session?.accessToken
                                camera.sendSelectionToOpenAI(
                                    prompt: analysisPrompt(location: context),
                                    useWebSearch: useWebSearch,
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
                                let (context, useWebSearch) = resolveLocationContext()
                                zipFieldFocused = false
                                manualTextFocused = false
                                lastAnalysisSource = .photo
                                let accessToken = auth.session?.accessToken
                                camera.sendSelectionToOpenAI(
                                    prompt: analysisPrompt(location: context),
                                    useWebSearch: useWebSearch,
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
            if camera.capturedImage == nil {
                camera.startSession()
            }
        }
        .onDisappear {
            camera.stopSession()
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: camera.aiIsLoading)
        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: camera.aiParsedResult)
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
            guard let result = newValue, let raw = camera.aiResultText else { return }
            guard lastSavedJSON != raw else { return }
            let previewImage = lastAnalysisSource == .photo ? camera.previewImageForHistory() : nil
            switch history.add(result: result, rawJSON: raw, source: lastAnalysisSource, image: previewImage) {
            case .added(let entry):
                if auth.autoSyncImpactEnabled {
                    auth.submitImpact(entry: entry, history: history)
                }
                if entry.source == .text {
                    scoreNotice = "Thanks for recycling - text entries won't add to your score."
                } else {
                    scoreNotice = nil
                }
            case .duplicate(let entry):
                if auth.autoSyncImpactEnabled {
                    auth.submitImpact(entry: entry, history: history)
                }
                scoreNotice = "Thanks for recycling - this won't add to your score."
            }
            lastSavedJSON = raw
            if !auth.isSignedIn {
                auth.refreshGuestQuota()
            }
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            camera.updateOrientation()
        }
        .onDisappear {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            camera.updateOrientation()
        }
    }
}

private struct ConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = ConfettiEmitterView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear

        let colors: [UIColor] = [
            UIColor(red: 0.2, green: 0.9, blue: 0.55, alpha: 1.0),
            UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),
            UIColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 1.0),
            UIColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1.0)
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

private final class ConfettiEmitterView: UIView {
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
