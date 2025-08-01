import Photos
import Foundation
import SwiftUI
import AVFoundation
import os

private let logger = Logger(subsystem: "com.yourapp.blur", category: "video")

class VideoBlurViewModel: ObservableObject {
    // State properties
    @Published var selectedVideoURL: URL?
    @Published var processedVideoURL: URL?
    @Published var isProcessing = false
    @Published var showVideoPicker = false
    @Published var showSaveAlert = false
    @Published var saveSuccess = false
    @Published var errorMessage: String?
    @Published var showFaceGallery = false
    @Published var showBlurStrengthAdjustment = false
    @Published var blurStrength: Double = 15
    @Published var detectedFaces: [DetectedFace] = []
    @Published var selectedFaceIDs: Set<UUID> = []
    @Published var firstFrameImage: UIImage? = nil
    
    // MARK: - Business Logic Methods
    
    func scanVideoForFaces(from url: URL) {
        detectedFaces = []
        selectedFaceIDs = []
        showFaceGallery = false
        let asset = AVAsset(url: url)
        let duration = asset.duration
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let totalSeconds = Int(CMTimeGetSeconds(duration))
        let times = stride(from: 0, to: totalSeconds, by: 1).map { CMTime(seconds: Double($0), preferredTimescale: 600) }
        let context = CIContext()
        let detector = CIDetector(ofType: CIDetectorTypeFace, context: context, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        DispatchQueue.global(qos: .userInitiated).async {
            var foundFaces: [DetectedFace] = []
            for time in times {
                guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
                let ciImage = CIImage(cgImage: cgImage)
                let features = detector?.features(in: ciImage) as? [CIFaceFeature] ?? []
                for feature in features {
                    let faceRect = feature.bounds
                    if let faceCg = cgImage.cropping(to: faceRect) {
                        let faceImg = UIImage(cgImage: faceCg)
                        let detected = DetectedFace(image: faceImg, boundingBox: faceRect, time: time)
                        foundFaces.append(detected)
                    }
                }
            }
            DispatchQueue.main.async {
                var facesToShow = foundFaces
                if facesToShow.isEmpty {
                    if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                        let width = CGFloat(cgImage.width)
                        let height = CGFloat(cgImage.height)
                        let side = min(width, height) / 4
                        let rect = CGRect(x: (width - side)/2, y: (height - side)/2, width: side, height: side)
                        if let faceCg = cgImage.cropping(to: rect) {
                            let faceImg = UIImage(cgImage: faceCg)
                            let dummy = DetectedFace(image: faceImg, boundingBox: rect, time: .zero)
                            facesToShow = [dummy]
                        }
                    }
                }
                self.detectedFaces = facesToShow
                self.showFaceGallery = true
            }
        }
    }

    func processVideoWithSelectedFaces() {
        guard let inputURL = selectedVideoURL else { logger.error("No selectedVideoURL"); return }
        isProcessing = true
        processedVideoURL = nil
        errorMessage = nil
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("blurred_\(UUID().uuidString).mov")
        let asset = AVAsset(url: inputURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            isProcessing = false
            errorMessage = "No video track found."
            showSaveAlert = true
            logger.error("No video track found in asset")
            return
        }
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            isProcessing = false
            errorMessage = "Could not create composition track."
            showSaveAlert = true
            logger.error("Could not create composition track")
            return
        }
        do {
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
        } catch {
            isProcessing = false
            errorMessage = "Failed to insert time range."
            showSaveAlert = true
            logger.error("Failed to insert time range: \(String(describing: error))")
            return
        }
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = videoTrack.naturalSize
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(videoTrack.preferredTransform, at: .zero)
        layerInstruction.setOpacityRamp(fromStartOpacity: 1.0, toEndOpacity: 1.0, timeRange: instruction.timeRange)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        videoComposition.customVideoCompositorClass = SelectedFaceBlurVideoCompositor.self
        SelectedFaceBlurVideoCompositor.selectedFaceRects = selectedFaceIDs.compactMap { id in
            detectedFaces.first(where: { $0.id == id })?.boundingBox
        }
        SelectedFaceBlurVideoCompositor.blurStrength = blurStrength
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1280x720) else {
            isProcessing = false
            errorMessage = "Could not create export session."
            showSaveAlert = true
            logger.error("Could not create export session")
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                self.isProcessing = false
                if exportSession.status == .completed {
                    self.processedVideoURL = outputURL
                    logger.debug("processVideoWithSelectedFaces set processedVideoURL: \(outputURL.path, privacy: .public)")
                } else {
                    self.errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
                    self.showSaveAlert = true
                    logger.error("Export session failed: \(String(describing: exportSession.error))")
                }
            }
        }
    }

    func saveProcessedVideo() {
        guard let url = processedVideoURL else { return }
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized || status == .limited {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                }) { success, error in
                    DispatchQueue.main.async {
                        self.saveSuccess = success
                        self.errorMessage = error?.localizedDescription
                        self.showSaveAlert = true
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.saveSuccess = false
                    self.errorMessage = "Photo library access denied."
                    self.showSaveAlert = true
                }
            }
        }
    }

    func processVideo() {
        guard let inputURL = selectedVideoURL else { return }
        isProcessing = true
        processedVideoURL = nil
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("blurred_\(UUID().uuidString).mov")
        VideoBlurProcessor.processExistingVideo(inputURL: inputURL, outputURL: outputURL) { success, error in
            DispatchQueue.main.async {
                self.isProcessing = false
                if success {
                    self.processedVideoURL = outputURL
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Unknown error"
                    self.showSaveAlert = true
                }
            }
        }
    }
} 
