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
    
    //MARK: - OpenAI
    private let openAI = OpenAIResponsesClient()

    // MARK: - Camera
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private let output = AVCapturePhotoOutput()
    private var isConfigured = false

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
    func sendSelectionToOpenAI(prompt: String, useWebSearch: Bool, accessToken: String?) {
        guard isSelected else { return }

        let cutoutImage = makeSelectedSubjectCutout()
        let imageToSend: UIImage? = capturedImage ?? cutoutImage
        let contextImage = (cutoutImage == nil || capturedImage == nil) ? nil : cutoutImage

        guard let imageToSend else { return }

        aiIsLoading = true
        aiErrorText = nil
        aiResultText = nil
        aiParsedResult = nil

        Task {
            do {
                let text = try await openAI.analyzeImage(
                    prompt: prompt,
                    image: imageToSend,
                    contextImage: contextImage,
                    maxOutputTokens: 400,
                    useWebSearch: useWebSearch,
                    accessToken: accessToken
                )
                await MainActor.run {
                    self.aiResultText = text
                    if let parsed = self.parseResponse(text) {
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
    func sendTextToOpenAI(prompt: String, itemText: String, useWebSearch: Bool, accessToken: String?) {
        let trimmed = itemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        aiIsLoading = true
        aiErrorText = nil
        aiResultText = nil
        aiParsedResult = nil

        Task {
            do {
                let text = try await openAI.analyzeText(
                    prompt: prompt,
                    maxOutputTokens: 400,
                    useWebSearch: useWebSearch,
                    accessToken: accessToken
                )
                await MainActor.run {
                    self.aiResultText = text
                    if let parsed = self.parseResponse(text) {
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

        // Work in POINTS for mapping, then convert to PIXELS for mask sampling
        let iwPts = img.size.width
        let ihPts = img.size.height
        let vw = viewSize.width
        let vh = viewSize.height

        let scale = max(vw / iwPts, vh / ihPts) // aspectFill
        let dw = iwPts * scale
        let dh = ihPts * scale
        let x0 = (vw - dw) * 0.5
        let y0 = (vh - dh) * 0.5

        let ixPts = (viewPoint.x - x0) / scale
        let iyPts = (viewPoint.y - y0) / scale

        if ixPts < 0 || iyPts < 0 || ixPts >= iwPts || iyPts >= ihPts {
            clearSelection()
            return
        }

        let ix = Int((ixPts * img.scale).rounded(.down))
        let iy = Int((iyPts * img.scale).rounded(.down))

        if let hitIndex = instanceMasks.firstIndex(where: { isMaskHit(in: $0.maskBuffer, x: ix, y: iy) }) {
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

    private func isMaskHit(in pb: CVPixelBuffer, x: Int, y: Int) -> Bool {
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard x >= 0, y >= 0, x < w, y < h else { return false }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pb) else { return false }
        let bpr = CVPixelBufferGetBytesPerRow(pb)

        @inline(__always) func sample(_ sx: Int, _ sy: Int) -> UInt8 {
            let row = base.advanced(by: sy * bpr)
            return row.assumingMemoryBound(to: UInt8.self)[sx]
        }

        // sample both y and flipped-y (robust to coordinate flips)
        let v1 = sample(x, y)
        let fy = h - 1 - y
        let v2 = (fy >= 0 && fy < h) ? sample(x, fy) : 0

        let threshold: UInt8 = 80
        return v1 > threshold || v2 > threshold
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
            self.capturedImage = fixed
            self.isSelected = false
            self.glowImage = nil
            self.fillImage = nil
            self.instanceMasks = []
            self.selectedInstanceIndex = nil
            self.selectedMaskCI = nil
            self.stopSession()
        }

        buildOverlays(from: cg, uiImage: fixed, dismissCaptureOnNoItems: false)
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
            self.noItemDetected = true
            if dismissCaptureOnNoItems {
                self.capturedImage = nil
                self.capturedCI = nil
                self.startSession()
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
            return sanitizeResult(decoded)
        }
        if let extracted = extractJSONCandidate(from: text),
           let decoded = decodeResult(from: extracted) {
            return sanitizeResult(decoded)
        }
        guard let parsed = parseKeyValueResponse(text) else { return nil }
        return sanitizeResult(parsed)
    }

    private func decodeResult(from text: String) -> AIRecyclingResult? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AIRecyclingResult.self, from: data)
    }

    private func parseKeyValueResponse(_ text: String) -> AIRecyclingResult? {
        var map: [String: String] = [:]

        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .forEach { line in
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    map[key] = value
                }
            }

        guard
            let item = map["ITEM"],
            let material = map["MATERIAL"],
            let recyclableRaw = map["RECYCLABLE"],
            let bin = map["BIN"]
        else { return nil }

        let lower = recyclableRaw.lowercased()
        let recyclable: Bool
        if lower.contains("no") || lower.contains("false") || lower.contains("not recyclable") {
            recyclable = false
        } else if lower.contains("yes") || lower.contains("true") || lower.contains("recyclable") {
            recyclable = true
        } else {
            recyclable = false
        }

        let notes = map["NOTES"] ?? ""
        return AIRecyclingResult(item: item, material: material, recyclable: recyclable, bin: bin, notes: notes)
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

    private func sanitizeResult(_ result: AIRecyclingResult) -> AIRecyclingResult {
        AIRecyclingResult(
            item: sanitizeOutputValue(result.item),
            material: sanitizeOutputValue(result.material),
            recyclable: result.recyclable,
            bin: sanitizeOutputValue(result.bin),
            notes: sanitizeOutputValue(result.notes)
        )
    }

    private func sanitizeOutputValue(_ value: String) -> String {
        var text = value
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
        text = text.replacingOccurrences(of: "  ", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AIRecyclingResult: Codable, Equatable {
    let item: String
    let material: String
    let recyclable: Bool
    let bin: String
    let notes: String
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
