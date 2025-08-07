import Foundation
import AVFoundation
import Vision
import CoreImage
import os

private let logger = Logger(subsystem: "com.yourapp.blur", category: "video")

class VideoBlurProcessor {
    static func processExistingVideo(inputURL: URL, outputURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        let asset = AVAsset(url: inputURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(false, NSError(domain: "VideoProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"]))
            return
        }
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        // Add video track
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(false, NSError(domain: "VideoProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create composition track"]))
            return
        }
        do {
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
        } catch {
            completion(false, error)
            return
        }
        // Set up video composition
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = videoTrack.naturalSize
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(videoTrack.preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        // Apply face blur filter
        videoComposition.customVideoCompositorClass = FaceBlurVideoCompositor.self
        // Export
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(false, NSError(domain: "VideoProcessing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"]))
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(true, nil)
                case .failed:
                    completion(false, exportSession.error)
                default:
                    completion(false, NSError(domain: "VideoProcessing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Export cancelled or unknown error"]))
                }
            }
        }
    }
}

// MARK: - Video Processor for Blur Masks

class VideoProcessor {
    
    // MARK: - Public Methods
    
    static func processVideo(
        inputURL: URL,
        blurMasks: [BlurMask],
        onProgress: @escaping (Float) -> Void
    ) async throws -> URL {
        
        let asset = AVAsset(url: inputURL)
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("blurred_\(UUID().uuidString).mov")
        
        // Create composition
        let composition = AVMutableComposition()
        guard let videoTrack = asset.tracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw VideoProcessingError.noVideoTrack
        }
        
        // Insert video track
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: asset.duration),
            of: videoTrack,
            at: .zero
        )
        
        // Create video composition
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = videoTrack.naturalSize
        
        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        // Preserve original transform to maintain orientation
        layerInstruction.setTransform(videoTrack.preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        
        // Set custom compositor
        videoComposition.customVideoCompositorClass = BlurMaskVideoCompositor.self
        
        // Configure compositor with blur masks
        BlurMaskVideoCompositor.configure(
            blurMasks: blurMasks,
            videoSize: videoTrack.naturalSize
        )
        
        // Create export session with original quality
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoProcessingError.exportSessionCreationFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        
        // Export video
        return try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume(returning: outputURL)
                case .failed:
                    continuation.resume(throwing: VideoProcessingError.exportFailed(exportSession.error))
                case .cancelled:
                    continuation.resume(throwing: VideoProcessingError.exportCancelled)
                default:
                    continuation.resume(throwing: VideoProcessingError.unknownError)
                }
            }
        }
    }
}

// MARK: - Video Compositor

class BlurMaskVideoCompositor: NSObject, AVVideoCompositing {
    
    // MARK: - Static Configuration
    private static var blurMasks: [BlurMask] = []
    private static var videoSize: CGSize = .zero
    private static var faceTracker: VNSequenceRequestHandler?
    
    static func configure(blurMasks: [BlurMask], videoSize: CGSize) {
        self.blurMasks = blurMasks
        self.videoSize = videoSize
        self.faceTracker = VNSequenceRequestHandler()
    }
    
    // MARK: - AVVideoCompositing Properties
    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferOpenGLESCompatibilityKey as String: true
    ]
    
    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferOpenGLESCompatibilityKey as String: true
    ]
    
    // MARK: - Private Properties
    private let processingQueue = DispatchQueue(label: "video.compositor.queue", qos: .userInitiated)
    private let ciContext = CIContext()
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    
    // MARK: - Initialization
    override init() {
        super.init()
        setupFaceDetection()
    }
    
    // MARK: - AVVideoCompositing Methods
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Handle render context changes if needed
    }
    
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        processingQueue.async {
            self.processRequest(asyncVideoCompositionRequest)
        }
    }
    
    // MARK: - Private Methods
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest()
    }
    
    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let trackIDNumber = request.sourceTrackIDs[0] as? NSNumber else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 1, userInfo: nil))
            return
        }
        
        let trackID = CMPersistentTrackID(truncating: trackIDNumber)
        guard let sourcePixelBuffer = request.sourceFrame(byTrackID: trackID) else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 2, userInfo: nil))
            return
        }
        
        let ciImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
        let processedImage = applyBlurMasks(to: ciImage, at: request.compositionTime)
        
        guard let outputPixelBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 3, userInfo: nil))
            return
        }
        
        ciContext.render(processedImage, to: outputPixelBuffer)
        request.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    
    private func applyBlurMasks(to image: CIImage, at time: CMTime) -> CIImage {
        var outputImage = image
        
        // Detect faces in current frame
        let faces = detectFaces(in: image)
        
        // Apply blur to each mask area
        for mask in Self.blurMasks {
            if let faceRect = findBestMatchingFace(for: mask, in: faces) {
                outputImage = applyBlur(to: outputImage, in: faceRect)
            } else {
                // If no face found, apply blur to the mask area directly
                let maskRect = convertMaskToImageCoordinates(mask)
                outputImage = applyBlur(to: outputImage, in: maskRect)
            }
        }
        
        return outputImage
    }
    
    private func detectFaces(in image: CIImage) -> [CGRect] {
        guard let request = faceDetectionRequest else { return [] }
        
        let handler = VNImageRequestHandler(ciImage: image, options: [:])
        try? handler.perform([request])
        
        return request.results?.compactMap { observation in
            // Convert normalized coordinates to image coordinates
            let imageSize = image.extent.size
            return CGRect(
                x: observation.boundingBox.origin.x * imageSize.width,
                y: observation.boundingBox.origin.y * imageSize.height,
                width: observation.boundingBox.width * imageSize.width,
                height: observation.boundingBox.height * imageSize.height
            )
        } ?? []
    }
    
    private func findBestMatchingFace(for mask: BlurMask, in faces: [CGRect]) -> CGRect? {
        let maskCenter = convertMaskToImageCoordinates(mask).center
        
        // Find the closest face to the mask center
        return faces.min { face1, face2 in
            let distance1 = distance(from: maskCenter, to: face1.center)
            let distance2 = distance(from: maskCenter, to: face2.center)
            return distance1 < distance2
        }
    }
    
    private func convertMaskToImageCoordinates(_ mask: BlurMask) -> CGRect {
        // Use actual video dimensions instead of hardcoded values
        let scaleX = Self.videoSize.width / 300 // Assuming overlay width is 300
        let scaleY = Self.videoSize.height / 300 // Assuming overlay height is 300
        
        let centerX = mask.center.x * scaleX
        let centerY = mask.center.y * scaleY
        let radius = mask.radius * min(scaleX, scaleY)
        
        return CGRect(
            x: centerX - radius,
            y: centerY - radius,
            width: radius * 2,
            height: radius * 2
        )
    }
    
    private func applyBlur(to image: CIImage, in rect: CGRect) -> CIImage {
        let expandedRect = rect.insetBy(dx: -20, dy: -20)
        let croppedImage = image.cropped(to: expandedRect)
        
        let blurFilter = CIFilter(name: "CIGaussianBlur")!
        blurFilter.setValue(croppedImage, forKey: kCIInputImageKey)
        blurFilter.setValue(100.0, forKey: kCIInputRadiusKey) // Increased blur strength from 50 to 100
        
        guard let blurredImage = blurFilter.outputImage else { return image }
        
        let composite = CIFilter(name: "CISourceOverCompositing")!
        composite.setValue(blurredImage, forKey: kCIInputImageKey)
        composite.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        return composite.outputImage ?? image
    }
    
    private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
        let dx = point1.x - point2.x
        let dy = point1.y - point2.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - Extensions

extension CGRect {
    var center: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}

// MARK: - Error Types

enum VideoProcessingError: Error, LocalizedError {
    case noVideoTrack
    case exportSessionCreationFailed
    case exportFailed(Error?)
    case exportCancelled
    case unknownError
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in the selected file"
        case .exportSessionCreationFailed:
            return "Failed to create video export session"
        case .exportFailed(let error):
            return "Video export failed: \(error?.localizedDescription ?? "Unknown error")"
        case .exportCancelled:
            return "Video export was cancelled"
        case .unknownError:
            return "An unknown error occurred during video processing"
        }
    }
} 