//
//  CameraViewModel.swift
//  Recyclability
//

import SwiftUI
import Combine
import AVFoundation
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Photos

final class CameraViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {

    // MARK: - Public state
    @Published var capturedImage: UIImage?
    @Published var glowImage: UIImage?
    @Published var fillImage: UIImage?
    @Published var isSelected: Bool = false
    @Published var aiResultText: String?
    @Published var aiParsedResult: AIRecyclingResult?
    @Published var aiIsLoading: Bool = false
    @Published var aiErrorText: String?
    @Published var cameraErrorText: String?
    @Published var noItemDetected: Bool = false
    @Published var hapticsEnabled: Bool = true
    @Published var zoomFactor: CGFloat = 1.0

    private var latestAnalysisRequestID = UUID()

    private let maxZoomLimit: CGFloat = 10.0
    private var minZoomFactor: CGFloat = 1.0
    private var maxZoomFactor: CGFloat = 10.0
    
    //MARK: - OpenAI
    private let openAI = OpenAIResponsesClient()

    // MARK: - Camera
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let output = AVCapturePhotoOutput()
    private var isConfigured = false
    private var videoDevice: AVCaptureDevice?

    // MARK: - CI
    private let ciContext = CIContext()

    // MARK: - Mask storage
    private struct InstanceMaskItem {
        let maskBuffer: CVPixelBuffer
        let scaledMaskCI: CIImage
    }

    private var instanceMasks: [InstanceMaskItem] = []
    private var selectedInstanceIndex: Int?
    private var selectedMaskCI: CIImage?

    // Keep the selected mask + captured CI for export (aligned to photo extent)
    private var capturedCI: CIImage?

    override init() {
        super.init()
    }

    private func ensureCameraAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if !granted {
                    self.setCameraError("Camera access is required to scan items. Enable it in Settings.")
                }
                completion(granted)
            }
        default:
            setCameraError("Camera access is required to scan items. Enable it in Settings.")
            completion(false)
        }
    }

    private func configureSessionIfNeeded() {
        if isConfigured { return }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video) else {
            session.commitConfiguration()
            setCameraError("Camera unavailable.")
            return
        }
        videoDevice = device
        maxZoomFactor = min(device.activeFormat.videoMaxZoomFactor, maxZoomLimit)

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                session.commitConfiguration()
                setCameraError("Unable to access camera.")
                return
            }
        } catch {
            session.commitConfiguration()
            setCameraError("Unable to access camera.")
            return
        }

        if session.canAddOutput(output) {
            session.addOutput(output)
        } else {
            session.commitConfiguration()
            setCameraError("Unable to capture photos.")
            return
        }

        session.commitConfiguration()
        isConfigured = true
        clearCameraError()
    }

    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async {
            guard let device = self.videoDevice else { return }
            let clamped = max(self.minZoomFactor, min(factor, self.maxZoomFactor))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.zoomFactor = clamped
                }
            } catch {
                // Ignore zoom failure
            }
        }
    }

    private func setCameraError(_ message: String) {
        DispatchQueue.main.async {
            self.cameraErrorText = message
        }
    }

    private func clearCameraError() {
        DispatchQueue.main.async {
            self.cameraErrorText = nil
        }
    }

    func startSession() {
        ensureCameraAccess { [weak self] granted in
            guard let self, granted else { return }
            self.sessionQueue.async {
                self.configureSessionIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func clearCapturedImage() {
        capturedImage = nil
        capturedCI = nil
    }

    func takePhoto() {
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        noItemDetected = false
        isSelected = false
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {

        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let raw = UIImage(data: data),
            let fixed = raw.normalizedUp(),
            let cg = fixed.cgImage
        else { return }

        // store CI for export
        self.capturedCI = CIImage(cgImage: cg)

        DispatchQueue.main.async {
            self.isSelected = false
            self.glowImage = nil
            self.fillImage = nil
            self.instanceMasks = []
            self.selectedInstanceIndex = nil
            self.selectedMaskCI = nil
        }

        buildOverlays(from: cg, uiImage: fixed, dismissCaptureOnNoItems: true)
    }
    
    @MainActor
    func sendSelectionToOpenAI(location: LocationContext, accessToken: String?) {
        guard isSelected else { return }
        let requestID = UUID()
        latestAnalysisRequestID = requestID

        let cutoutImage = makeSelectedSubjectCutout()
        // Keep full-frame as primary for robust identification, with cutout as optional context.
        let imageToSend: UIImage? = capturedImage ?? cutoutImage
        let contextImage = (cutoutImage == nil || capturedImage == nil) ? nil : cutoutImage

        guard let imageToSend else { return }

        aiIsLoading = true
        aiErrorText = nil
        aiResultText = nil
        aiParsedResult = nil

        Task {
            do {
                let text = try await analyzeImageWithRetry(
                    image: imageToSend,
                    contextImage: contextImage,
                    itemText: nil,
                    location: location,
                    accessToken: accessToken
                )
                let parsed = self.parseResponse(text)
                await MainActor.run {
                    guard self.latestAnalysisRequestID == requestID else { return }
                    self.aiResultText = text
                    if let parsed {
                        self.aiParsedResult = parsed
                        self.aiErrorText = nil
                    } else {
                        self.aiParsedResult = nil
                        self.aiErrorText = "Couldn't parse response. Please try again."
                    }
                    self.aiIsLoading = false
                }
            } catch {
                await MainActor.run {
                    guard self.latestAnalysisRequestID == requestID else { return }
                    self.aiErrorText = error.localizedDescription
                    self.aiParsedResult = nil
                    self.aiIsLoading = false
                }
            }
        }
    }

    func previewImageForHistory() -> UIImage? {
        return makeSelectedSubjectCutout() ?? capturedImage
    }

    @MainActor
    func sendTextToOpenAI(itemText: String, location: LocationContext, accessToken: String?) {
        let trimmed = itemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let requestID = UUID()
        latestAnalysisRequestID = requestID

        aiIsLoading = true
        aiErrorText = nil
        aiResultText = nil
        aiParsedResult = nil

        Task {
            do {
                let text = try await analyzeTextWithRetry(
                    itemText: trimmed,
                    location: location,
                    accessToken: accessToken
                )
                let parsed = self.parseResponse(text)
                await MainActor.run {
                    guard self.latestAnalysisRequestID == requestID else { return }
                    self.aiResultText = text
                    if let parsed {
                        self.aiParsedResult = parsed
                        self.aiErrorText = nil
                    } else {
                        self.aiParsedResult = nil
                        self.aiErrorText = "Couldn't parse response. Please try again."
                    }
                    self.aiIsLoading = false
                }
            } catch {
                await MainActor.run {
                    guard self.latestAnalysisRequestID == requestID else { return }
                    self.aiErrorText = error.localizedDescription
                    self.aiParsedResult = nil
                    self.aiIsLoading = false
                }
            }
        }
    }

    // MARK: - Tap handling
    func handleTap(at viewPoint: CGPoint, in viewSize: CGSize) {
        guard let img = capturedImage else { return }
        guard !instanceMasks.isEmpty else { return }

        // Map view -> image pixels using the same basis as the mask buffers.
        let vw = viewSize.width
        let vh = viewSize.height
        let iwPx = capturedCI?.extent.width ?? (img.size.width * img.scale)
        let ihPx = capturedCI?.extent.height ?? (img.size.height * img.scale)

        let scale = max(vw / iwPx, vh / ihPx) // aspectFill
        let dw = iwPx * scale
        let dh = ihPx * scale
        let x0 = (vw - dw) * 0.5
        let y0 = (vh - dh) * 0.5

        let ixPx = (viewPoint.x - x0) / scale
        let iyPx = (viewPoint.y - y0) / scale

        if ixPx < 0 || iyPx < 0 || ixPx >= iwPx || iyPx >= ihPx {
            clearSelection()
            return
        }

        let ix = Int(ixPx.rounded(.down))
        let iy = Int(iyPx.rounded(.down))

        if let hitIndex = bestMaskIndex(x: ix, y: iy) {
            if selectedInstanceIndex == hitIndex {
                clearSelection()
            } else {
                selectInstance(at: hitIndex)
            }
        } else {
            clearSelection()
        }
    }

    private func clearSelection() {
        selectedInstanceIndex = nil
        selectedMaskCI = nil
        fillImage = nil
        isSelected = false
    }

    private func selectInstance(at index: Int) {
        selectedInstanceIndex = index
        selectedMaskCI = instanceMasks[index].scaledMaskCI
        isSelected = true
        fillImage = makeFillImage(from: instanceMasks[index].scaledMaskCI)
    }

    private func bestMaskIndex(x: Int, y: Int) -> Int? {
        var bestIndex: Int?
        var bestScore: Int = 0
        for (idx, mask) in instanceMasks.enumerated() {
            let score = maskHitScore(in: mask.maskBuffer, x: x, y: y)
            if score > bestScore {
                bestScore = score
                bestIndex = idx
            }
        }
        return bestIndex
    }

    private func maskHitScore(in pb: CVPixelBuffer, x: Int, y: Int) -> Int {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard x >= 0, y >= 0, x < w, y < h else { return 0 }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return 0 }
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        @inline(__always) func sample(_ sx: Int, _ sy: Int) -> UInt8 {
            let row = base.advanced(by: sy * bpr)
            return row.assumingMemoryBound(to: UInt8.self)[sx]
        }

        let threshold: UInt8 = 80
        let radius = 3
        var score = 0
        for dy in -radius...radius {
            let yy = y + dy
            if yy < 0 || yy >= h { continue }
            let fy = h - 1 - yy
            for dx in -radius...radius {
                let xx = x + dx
                if xx < 0 || xx >= w { continue }
                let v1 = sample(xx, yy)
                if v1 > threshold { score += 1 }
                if fy >= 0 && fy < h {
                    let v2 = sample(xx, fy)
                    if v2 > threshold { score += 1 }
                }
            }
        }
        return score
    }

    // MARK: - Export / Save selected subject
    /// Creates an image where ONLY the selected subject is visible (background transparent),
    /// saves a PNG in Documents, and also saves to Photos.
    func saveSelectedSubject() {
        guard isSelected else { return }
        guard let cutout = makeSelectedSubjectCutout() else { return }

        // 1) Save PNG into app Documents (best for later API upload)
        if let url = writePNGToDocuments(cutout) {
            print("Saved cutout PNG to:", url)
        }

        // 2) Save to Photos (requires Info.plist add-usage string)
        saveToPhotos(cutout)
    }
    
    // MARK: - Import from Photo Library
    func useImportedPhoto(_ image: UIImage) {
        guard let fixed = image.normalizedUp(),
              let cg = fixed.cgImage
        else { return }

        // Store CI for export
        self.capturedCI = CIImage(cgImage: cg)
        self.noItemDetected = false

        DispatchQueue.main.async {
            self.isSelected = false
            self.glowImage = nil
            self.fillImage = nil
            self.instanceMasks = []
            self.selectedInstanceIndex = nil
            self.selectedMaskCI = nil
        }

        buildOverlays(from: cg, uiImage: fixed, dismissCaptureOnNoItems: true)
    }


    private func makeSelectedSubjectCutout() -> UIImage? {
        guard let capturedCI = capturedCI else { return nil }
        guard let maskCI = selectedMaskCI else { return nil }

        let extent = capturedCI.extent
        let clearBG = CIImage(color: .clear).cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = capturedCI
        blend.backgroundImage = clearBG
        blend.maskImage = maskCI

        guard let out = blend.outputImage?.cropped(to: extent) else { return nil }
        guard let outCG = ciContext.createCGImage(out, from: extent) else { return nil }

        let scale = capturedImage?.scale ?? 1.0
        return UIImage(cgImage: outCG, scale: scale, orientation: .up)
    }

    private func writePNGToDocuments(_ image: UIImage) -> URL? {
        guard let data = image.pngData() else { return nil }
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = dir.appendingPathComponent("selected_subject_\(Int(Date().timeIntervalSince1970)).png")
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            print("Failed writing PNG:", error)
            return nil
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        let performSave = {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }

        if #available(iOS 14, *) {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited {
                    DispatchQueue.main.async { performSave() }
                } else {
                    print("Photos permission not granted:", status.rawValue)
                }
            }
        } else {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    DispatchQueue.main.async { performSave() }
                } else {
                    print("Photos permission not granted:", status.rawValue)
                }
            }
        }
    }

    private func handleNoItems(dismissCaptureOnNoItems: Bool) {
        DispatchQueue.main.async {
            self.instanceMasks = []
            self.selectedInstanceIndex = nil
            self.selectedMaskCI = nil
            self.glowImage = nil
            self.fillImage = nil
            self.isSelected = false
            // Retrigger the no-item signal reliably, even on back-to-back attempts.
            self.noItemDetected = false
            if dismissCaptureOnNoItems {
                self.capturedImage = nil
                self.capturedCI = nil
                self.startSession()
            }
            DispatchQueue.main.async {
                self.noItemDetected = true
            }
        }
    }

    // MARK: - Overlay generation (alignment-fixed)
    private func buildOverlays(from cgImage: CGImage, uiImage: UIImage, dismissCaptureOnNoItems: Bool) {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)

        let imageCI = CIImage(cgImage: cgImage)
        let extent = imageCI.extent

        let targetW = Int(extent.width)
        let targetH = Int(extent.height)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                guard let obs = request.results?.first as? VNInstanceMaskObservation else {
                    self.handleNoItems(dismissCaptureOnNoItems: dismissCaptureOnNoItems)
                    return
                }

                guard !obs.allInstances.isEmpty else {
                    self.handleNoItems(dismissCaptureOnNoItems: dismissCaptureOnNoItems)
                    return
                }

                func scaledMaskCI(from rawMaskCI: CIImage) -> CIImage {
                    let sx = extent.width / rawMaskCI.extent.width
                    let sy = extent.height / rawMaskCI.extent.height
                    return rawMaskCI
                        .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
                        .cropped(to: extent)
                }

                let combinedMaskBuffer = try obs.generateScaledMaskForImage(
                    forInstances: obs.allInstances,
                    from: handler
                )
                let combinedMaskCI = scaledMaskCI(from: CIImage(cvPixelBuffer: combinedMaskBuffer))

                // Phase 1: hollow outline for all instances
                let outline = self.morphologyGradient(combinedMaskCI, radius: 5).cropped(to: extent)
                let outlineBlur = outline
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 14])
                    .cropped(to: extent)

                let glowCI = self.falseColor(
                    outlineBlur,
                    background: .black,
                    subject: CIColor(red: 0.45, green: 0.65, blue: 1.0)
                ).cropped(to: extent)

                guard let glowCG = self.ciContext.createCGImage(glowCI, from: extent) else { return }
                let glowUI = UIImage(cgImage: glowCG, scale: uiImage.scale, orientation: .up)

                var newMasks: [InstanceMaskItem] = []
                newMasks.reserveCapacity(obs.allInstances.count)

                for instance in obs.allInstances {
                    let instanceBuffer = try obs.generateScaledMaskForImage(
                        forInstances: [instance],
                        from: handler
                    )
                    let instanceMaskCI = scaledMaskCI(from: CIImage(cvPixelBuffer: instanceBuffer))

                    guard let oneChannel = Self.makeOneComponent8Buffer(width: targetW, height: targetH) else { continue }
                    self.ciContext.render(instanceMaskCI, to: oneChannel)

                    newMasks.append(InstanceMaskItem(maskBuffer: oneChannel, scaledMaskCI: instanceMaskCI))
                }

                DispatchQueue.main.async {
                    if self.capturedImage == nil {
                        self.capturedImage = uiImage
                    }
                    self.instanceMasks = newMasks
                    self.selectedInstanceIndex = nil
                    self.selectedMaskCI = nil
                    self.glowImage = glowUI
                    self.fillImage = nil
                    self.isSelected = false
                    self.noItemDetected = false
                    self.stopSession()
                }

            } catch {
                print("Overlay generation failed:", error)
                self.handleNoItems(dismissCaptureOnNoItems: dismissCaptureOnNoItems)
            }
        }
    }

    // MARK: - CI helpers
    private func morphologyGradient(_ input: CIImage, radius: Float) -> CIImage {
        if let f = CIFilter(name: "CIMorphologyGradient") {
            f.setValue(input, forKey: kCIInputImageKey)
            f.setValue(radius, forKey: kCIInputRadiusKey)
            return f.outputImage ?? input
        } else {
            let edges = CIFilter.edges()
            edges.inputImage = input
            edges.intensity = 12
            return edges.outputImage ?? input
        }
    }

    private func falseColor(_ input: CIImage, background: CIColor, subject: CIColor) -> CIImage {
        let tint = CIFilter.falseColor()
        tint.inputImage = input
        tint.color0 = background
        tint.color1 = subject
        return tint.outputImage ?? input
    }

    private func gradientFillMasked(by mask: CIImage, extent: CGRect) -> CIImage {
        let grad = CIFilter.linearGradient()
        grad.point0 = CGPoint(x: extent.minX, y: extent.midY)
        grad.point1 = CGPoint(x: extent.maxX, y: extent.midY)
        grad.color0 = CIColor(red: 0.45, green: 0.65, blue: 1.0)
        grad.color1 = CIColor(red: 0.65, green: 0.45, blue: 1.0)

        let gradImg = (grad.outputImage ?? CIImage(color: .clear)).cropped(to: extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = gradImg
        blend.backgroundImage = CIImage(color: .clear).cropped(to: extent)
        blend.maskImage = mask

        return blend.outputImage ?? gradImg
    }

    private func makeFillImage(from maskCI: CIImage) -> UIImage? {
        guard let capturedCI = capturedCI else { return nil }
        let extent = capturedCI.extent
        let fillCI = gradientFillMasked(by: maskCI, extent: extent).cropped(to: extent)
        guard let fillCG = ciContext.createCGImage(fillCI, from: extent) else { return nil }
        let scale = capturedImage?.scale ?? 1.0
        return UIImage(cgImage: fillCG, scale: scale, orientation: .up)
    }

    private static func makeOneComponent8Buffer(width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent8,
            attrs as CFDictionary,
            &pb
        )
        return (status == kCVReturnSuccess) ? pb : nil
    }

    // MARK: - Response parsing
    private func parseResponse(_ text: String) -> AIRecyclingResult? {
        if let decoded = decodeResult(from: text) {
            return sanitizeResult(decoded, fallbackText: text)
        }
        if let extracted = extractJSONCandidate(from: text),
           let decoded = decodeResult(from: extracted) {
            return sanitizeResult(decoded, fallbackText: text)
        }
        if let parsed = parseKeyValueResponse(text) {
            return sanitizeResult(parsed, fallbackText: text)
        }
        if let rescued = parseLooseResponse(text) {
            return sanitizeResult(rescued, fallbackText: text)
        }
        let fallback = AIRecyclingResult(
            item: "unknown",
            material: "unknown",
            recyclable: false,
            bin: "unknown",
            notes: "No special prep.",
            carbonSavedKg: 0
        )
        return sanitizeResult(fallback, fallbackText: text)
    }

    private func analyzeImageWithRetry(
        image: UIImage,
        contextImage: UIImage?,
        itemText: String?,
        location: LocationContext,
        accessToken: String?
    ) async throws -> String {
        return try await openAI.analyzeImage(
            image: image,
            contextImage: contextImage,
            itemText: itemText,
            location: location,
            accessToken: accessToken
        )
    }

    private func analyzeTextWithRetry(
        itemText: String,
        location: LocationContext,
        accessToken: String?
    ) async throws -> String {
        return try await openAI.analyzeText(
            itemText: itemText,
            location: location,
            accessToken: accessToken
        )
    }

    private func decodeResult(from text: String) -> AIRecyclingResult? {
        guard let data = text.data(using: .utf8) else { return nil }
        if let decoded = try? JSONDecoder().decode(AIRecyclingResult.self, from: data) {
            return decoded
        }
        return decodeFlexibleJSON(data)
    }

    private func decodeFlexibleJSON(_ data: Data) -> AIRecyclingResult? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }

        let object: [String: Any]?
        if let dict = json as? [String: Any] {
            object = flattenTopLevel(dict)
        } else if let array = json as? [[String: Any]] {
            object = array.first.map(flattenTopLevel)
        } else {
            object = nil
        }

        guard let object else { return nil }

        func stringValue(_ keys: [String]) -> String? {
            for key in keys {
                if let value = normalizedString(from: object[key]) { return value }
                if let value = normalizedString(from: object[key.lowercased()]) { return value }
                if let value = normalizedString(from: object[key.uppercased()]) { return value }
            }
            return nil
        }

        func boolValue(_ keys: [String]) -> Bool? {
            for key in keys {
                if let value = object[key] as? Bool { return value }
                if let value = object[key.lowercased()] as? Bool { return value }
                if let value = object[key.uppercased()] as? Bool { return value }
                if let num = object[key] as? NSNumber { return num.boolValue }
                if let num = object[key.lowercased()] as? NSNumber { return num.boolValue }
                if let num = object[key.uppercased()] as? NSNumber { return num.boolValue }
            }
            if let str = stringValue(keys)?.lowercased() {
                if str.contains("yes") || str.contains("true") || str.contains("recyclable") { return true }
                if str.contains("no") || str.contains("false") || str.contains("not recyclable") { return false }
            }
            return nil
        }

        func doubleValue(_ keys: [String]) -> Double? {
            for key in keys {
                if let value = normalizedDouble(from: object[key]) {
                    return max(0, value)
                }
                if let value = normalizedDouble(from: object[key.lowercased()]) {
                    return max(0, value)
                }
                if let value = normalizedDouble(from: object[key.uppercased()]) {
                    return max(0, value)
                }
            }
            return nil
        }

        let item = stringValue(["item", "item_name", "product", "name", "object", "category"]) ?? "unknown"
        let material = stringValue(["material", "primary_material", "composition"]) ?? "unknown"
        let notes = stringValue(["notes", "prep", "preparation", "instructions"]) ?? ""
        let bin = stringValue(["bin", "disposal", "destination", "where_to_put", "container"]) ?? "unknown"
        let recyclable = boolValue(["recyclable", "is_recyclable", "accepted"]) ?? inferRecyclable(from: bin)
        let carbonSavedKg = doubleValue([
            "carbonSavedKg",
            "carbon_saved_kg",
            "carbon_kg",
            "co2_saved_kg",
            "co2e_saved_kg",
            "carbon",
            "co2_saved",
        ]) ?? 0

        if item == "unknown", material == "unknown", bin == "unknown", notes.isEmpty {
            return nil
        }

        return AIRecyclingResult(
            item: item,
            material: material,
            recyclable: recyclable,
            bin: bin,
            notes: notes,
            carbonSavedKg: carbonSavedKg
        )
    }

    private func parseKeyValueResponse(_ text: String) -> AIRecyclingResult? {
        let map = extractKeyValueMap(from: text)

        let item = map["ITEM"] ?? map["PRODUCT"] ?? map["NAME"] ?? map["OBJECT"] ?? "unknown"
        let material = map["MATERIAL"] ?? map["PRIMARY_MATERIAL"] ?? "unknown"
        let notes = map["NOTES"] ?? map["PREP"] ?? map["INSTRUCTIONS"] ?? ""
        let bin = map["BIN"] ?? map["DISPOSAL"] ?? map["DESTINATION"] ?? map["WHERE_TO_PUT"] ?? "unknown"
        let carbonSavedKg = parseCarbonValue(
            map["CARBON_SAVED_KG"] ??
            map["CARBON_KG"] ??
            map["CO2_SAVED_KG"] ??
            map["CO2E_SAVED_KG"] ??
            map["CARBON"] ??
            map["CO2_SAVED"]
        ) ?? 0

        let recyclable: Bool
        if let recyclableRaw = map["RECYCLABLE"] {
            recyclable = parseRecyclableString(recyclableRaw) ?? inferRecyclable(from: bin)
        } else {
            recyclable = inferRecyclable(from: bin)
        }

        if item == "unknown", material == "unknown", bin == "unknown", notes.isEmpty {
            return nil
        }

        return AIRecyclingResult(
            item: item,
            material: material,
            recyclable: recyclable,
            bin: bin,
            notes: notes,
            carbonSavedKg: carbonSavedKg
        )
    }

    private func extractKeyValueMap(from text: String) -> [String: String] {
        let normalized = text.replacingOccurrences(of: "\r", with: "\n")
        var map: [String: String] = [:]
        let fields = [
            "NOTES", "PREP", "INSTRUCTIONS",
            "ITEM", "PRODUCT", "NAME", "OBJECT",
            "MATERIAL", "PRIMARY_MATERIAL",
            "RECYCLABLE",
            "BIN", "DISPOSAL", "DESTINATION", "WHERE_TO_PUT",
            "CARBON_SAVED_KG", "CARBON_KG", "CO2_SAVED_KG", "CO2E_SAVED_KG", "CARBON", "CO2_SAVED"
        ]
        let fieldsPattern = fields.joined(separator: "|")

        for field in fields {
            let pattern = "(?is)\\b" + field + "\\b\\s*[:=\\-]\\s*(.+?)(?=\\b(?:"
                + fieldsPattern
                + ")\\b\\s*[:=\\-]|$)"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(normalized.startIndex..., in: normalized)
            if let match = regex.firstMatch(in: normalized, options: [], range: range),
               let valueRange = Range(match.range(at: 1), in: normalized) {
                let raw = String(normalized[valueRange])
                let cleaned = raw
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-•*"))
                if !cleaned.isEmpty {
                    map[field] = cleaned
                }
            }
        }

        if map.isEmpty {
            for rawLine in normalized.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if line.isEmpty { continue }
                let parts = line.split(
                    maxSplits: 1,
                    omittingEmptySubsequences: false,
                    whereSeparator: { $0 == ":" || $0 == "=" }
                )
                if parts.count != 2 { continue }
                let key = parts[0].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).uppercased()
                let value = parts[1].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !key.isEmpty, !value.isEmpty {
                    map[key] = value
                }
            }
        }

        return map
    }

    private func parseLooseResponse(_ text: String) -> AIRecyclingResult? {
        let map = extractKeyValueMap(from: text)
        let item = map["ITEM"] ?? map["PRODUCT"] ?? map["NAME"] ?? map["OBJECT"] ?? "unknown"
        let material = map["MATERIAL"] ?? map["PRIMARY_MATERIAL"] ?? "unknown"
        let notes = map["NOTES"] ?? map["PREP"] ?? map["INSTRUCTIONS"] ?? ""
        let bin = map["BIN"] ?? map["DISPOSAL"] ?? map["DESTINATION"] ?? map["WHERE_TO_PUT"] ?? "unknown"
        let recyclable = (map["RECYCLABLE"].flatMap(parseRecyclableString)) ?? inferRecyclable(from: bin)
        let carbonSavedKg = parseCarbonValue(
            map["CARBON_SAVED_KG"] ??
            map["CARBON_KG"] ??
            map["CO2_SAVED_KG"] ??
            map["CO2E_SAVED_KG"] ??
            map["CARBON"] ??
            map["CO2_SAVED"]
        ) ?? 0

        if item == "unknown", material == "unknown", bin == "unknown", notes.isEmpty {
            return nil
        }
        return AIRecyclingResult(
            item: item,
            material: material,
            recyclable: recyclable,
            bin: bin,
            notes: notes,
            carbonSavedKg: carbonSavedKg
        )
    }

    private func inferRecyclable(from bin: String) -> Bool {
        let lower = bin.lowercased()
        if lower.contains("trash") || lower.contains("landfill") || lower.contains("garbage") {
            return false
        }
        if lower.contains("recycle") || lower.contains("curbside") {
            return true
        }
        return false
    }


    private func extractJSONCandidate(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let obj = sliceBetween(text: cleaned, open: "{", close: "}") {
            return obj
        }
        if let arr = sliceBetween(text: cleaned, open: "[", close: "]") {
            return arr
        }
        return nil
    }

    private func sliceBetween(text: String, open: Character, close: Character) -> String? {
        guard let start = text.firstIndex(of: open) else { return nil }
        guard let end = text.lastIndex(of: close), end > start else { return nil }
        return String(text[start...end])
    }

    private func sanitizeResult(_ result: AIRecyclingResult, fallbackText: String) -> AIRecyclingResult {
        let fallbackMap = extractKeyValueMap(from: fallbackText)
        let fallbackItem = fallbackMap["ITEM"] ?? fallbackMap["PRODUCT"] ?? fallbackMap["NAME"] ?? fallbackMap["OBJECT"]
        let fallbackMaterial = fallbackMap["MATERIAL"] ?? fallbackMap["PRIMARY_MATERIAL"]
        let fallbackBin = fallbackMap["BIN"] ?? fallbackMap["DISPOSAL"] ?? fallbackMap["DESTINATION"] ?? fallbackMap["WHERE_TO_PUT"]
        let fallbackNotes = fallbackMap["NOTES"] ?? fallbackMap["PREP"] ?? fallbackMap["INSTRUCTIONS"]
        let fallbackCarbon = fallbackMap["CARBON_SAVED_KG"]
            ?? fallbackMap["CARBON_KG"]
            ?? fallbackMap["CO2_SAVED_KG"]
            ?? fallbackMap["CO2E_SAVED_KG"]
            ?? fallbackMap["CARBON"]
            ?? fallbackMap["CO2_SAVED"]

        let sanitizedItem = sanitizedField(primary: result.item, fallback: fallbackItem, defaultValue: "unknown", avoidUnknownIfPossible: true)
        let sanitizedMaterial = sanitizedField(primary: result.material, fallback: fallbackMaterial, defaultValue: "unknown", avoidUnknownIfPossible: false)
        let sanitizedBin = sanitizedField(primary: result.bin, fallback: fallbackBin, defaultValue: "unknown", avoidUnknownIfPossible: false)
        let sanitizedNotes = sanitizedField(primary: result.notes, fallback: fallbackNotes, defaultValue: "No special prep.", avoidUnknownIfPossible: false)
        let itemUnknown = sanitizedItem.lowercased() == "unknown"
        let sanitizedRecyclable = itemUnknown ? false : result.recyclable
        let sanitizedCarbonValue = sanitizedRecyclable ? sanitizedCarbon(primary: result.carbonSavedKg, fallback: fallbackCarbon) : 0

        return AIRecyclingResult(
            item: sanitizedItem,
            material: sanitizedMaterial,
            recyclable: sanitizedRecyclable,
            bin: sanitizedBin,
            notes: sanitizedNotes,
            carbonSavedKg: sanitizedCarbonValue
        )
    }

    private func sanitizeOutputValue(_ value: String) -> String {
        var text = value
        text = text.replacingOccurrences(of: "^[\"'`\\s]+|[\"'`\\s]+$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)^(item|product|name|object|material|notes|prep|instructions|bin|disposal|destination|recyclable)\\s*[:=\\-]\\s*", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "www\\.\\S+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)check (your )?local (rules|guidelines|program)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)local (rules|guidelines) vary", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)verify with your municipality", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)contact your city", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)consult (your )?local program", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\(\\(\\s*$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\(\\s*$", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "  ", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizedField(
        primary: String,
        fallback: String?,
        defaultValue: String,
        avoidUnknownIfPossible: Bool
    ) -> String {
        let primaryClean = canonicalizeUnknownToken(sanitizeOutputValue(primary))
        if !primaryClean.isEmpty, !(avoidUnknownIfPossible && primaryClean == "unknown") {
            return primaryClean
        }
        if let fallback {
            let fallbackClean = canonicalizeUnknownToken(sanitizeOutputValue(fallback))
            if !fallbackClean.isEmpty, !(avoidUnknownIfPossible && fallbackClean == "unknown") {
                return fallbackClean
            }
        }
        return defaultValue
    }

    private func canonicalizeUnknownToken(_ value: String) -> String {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let unknownTokens: Set<String> = ["unknown", "unkown", "unknow", "unknwon", "unknowm", "n/a", "na", "none"]
        if unknownTokens.contains(normalized) {
            return "unknown"
        }
        return value
    }

    private func parseRecyclableString(_ value: String) -> Bool? {
        let lower = value.lowercased()
        if lower.contains("no") || lower.contains("false") || lower.contains("not recyclable") {
            return false
        }
        if lower.contains("yes") || lower.contains("true") || lower.contains("recyclable") {
            return true
        }
        return nil
    }

    private func parseCarbonValue(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let direct = Double(trimmed) {
            return max(0, direct)
        }
        let pattern = "(-?\\d+(?:\\.\\d+)?)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard
            let match = regex.firstMatch(in: trimmed, options: [], range: range),
            let valueRange = Range(match.range(at: 1), in: trimmed),
            let parsed = Double(trimmed[valueRange])
        else {
            return nil
        }
        return max(0, parsed)
    }

    private func sanitizedCarbon(primary: Double, fallback: String?) -> Double {
        if primary.isFinite, primary > 0 {
            return primary
        }
        if let fallbackParsed = parseCarbonValue(fallback) {
            return fallbackParsed
        }
        return 0
    }

    private func normalizedString(from raw: Any?) -> String? {
        guard let raw else { return nil }
        if let str = raw as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let num = raw as? NSNumber {
            return num.stringValue
        }
        if let arr = raw as? [Any] {
            for element in arr {
                if let value = normalizedString(from: element) {
                    return value
                }
            }
            return nil
        }
        if let dict = raw as? [String: Any] {
            for key in ["value", "text", "content", "label", "name", "item", "material", "bin", "notes"] {
                if let value = normalizedString(from: dict[key]) {
                    return value
                }
            }
        }
        return nil
    }

    private func normalizedDouble(from raw: Any?) -> Double? {
        guard let raw else { return nil }
        if let value = raw as? Double {
            return value
        }
        if let value = raw as? NSNumber {
            return value.doubleValue
        }
        if let value = raw as? String {
            return parseCarbonValue(value)
        }
        if let dict = raw as? [String: Any] {
            for key in ["value", "text", "content", "label", "carbon", "carbonSavedKg", "carbon_saved_kg"] {
                if let nested = normalizedDouble(from: dict[key]) {
                    return nested
                }
            }
        }
        return nil
    }

    private func flattenTopLevel(_ dict: [String: Any]) -> [String: Any] {
        var output = dict
        for key in ["result", "output", "response", "data", "analysis"] {
            if let nested = dict[key] as? [String: Any] {
                for (nestedKey, nestedValue) in nested where output[nestedKey] == nil {
                    output[nestedKey] = nestedValue
                }
            }
        }
        return output
    }
}

struct AIRecyclingResult: Codable, Equatable {
    let item: String
    let material: String
    let recyclable: Bool
    let bin: String
    let notes: String
    let carbonSavedKg: Double

    init(
        item: String,
        material: String,
        recyclable: Bool,
        bin: String,
        notes: String,
        carbonSavedKg: Double = 0
    ) {
        self.item = item
        self.material = material
        self.recyclable = recyclable
        self.bin = bin
        self.notes = notes
        self.carbonSavedKg = max(0, carbonSavedKg)
    }

    enum CodingKeys: String, CodingKey {
        case item
        case material
        case recyclable
        case bin
        case notes
        case carbonSavedKg
        case carbon_saved_kg
        case carbon_kg
        case co2_saved_kg
        case co2e_saved_kg
        case carbon
        case co2_saved
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        item = try container.decode(String.self, forKey: .item)
        material = try container.decode(String.self, forKey: .material)
        recyclable = try container.decode(Bool.self, forKey: .recyclable)
        bin = try container.decode(String.self, forKey: .bin)
        notes = try container.decode(String.self, forKey: .notes)

        let carbonCandidates: [Double?] = [
            try? container.decode(Double.self, forKey: .carbonSavedKg),
            try? container.decode(Double.self, forKey: .carbon_saved_kg),
            try? container.decode(Double.self, forKey: .carbon_kg),
            try? container.decode(Double.self, forKey: .co2_saved_kg),
            try? container.decode(Double.self, forKey: .co2e_saved_kg),
            try? container.decode(Double.self, forKey: .carbon),
            try? container.decode(Double.self, forKey: .co2_saved),
        ]
        carbonSavedKg = max(0, carbonCandidates.compactMap { $0 }.first ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item, forKey: .item)
        try container.encode(material, forKey: .material)
        try container.encode(recyclable, forKey: .recyclable)
        try container.encode(bin, forKey: .bin)
        try container.encode(notes, forKey: .notes)
        try container.encode(max(0, carbonSavedKg), forKey: .carbonSavedKg)
    }
}

// MARK: - UIImage normalization
private extension UIImage {
    func normalizedUp() -> UIImage? {
        if imageOrientation == .up { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = self.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
