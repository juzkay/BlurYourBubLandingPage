import Foundation
import AVFoundation
import CoreImage

class FaceBlurVideoCompositor: NSObject, AVVideoCompositing {
    var sourcePixelBufferAttributes: [String : Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferOpenGLESCompatibilityKey as String: true
    ]
    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferOpenGLESCompatibilityKey as String: true
    ]
    private let processingQueue = DispatchQueue(label: "video.compositor.queue")
    private let ciContext = CIContext()
    private var faceDetector: CIDetector?
    override init() {
        super.init()
        setupFaceDetector()
    }
    private func setupFaceDetector() {
        faceDetector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: ciContext,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        // Handle render context changes if needed
    }
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        processingQueue.async {
            self.processRequest(asyncVideoCompositionRequest)
        }
    }
    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let trackIDNumber = request.sourceTrackIDs[0] as? NSNumber else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 1, userInfo: nil))
            return
        }
        let trackID = CMPersistentTrackID(truncating: trackIDNumber)
        guard let sourcePixelBuffer = request.sourceFrame(byTrackID: trackID) else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 1, userInfo: nil))
            return
        }
        let ciImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
        let processedImage = applyFaceBlur(to: ciImage)
        guard let outputPixelBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 2, userInfo: nil))
            return
        }
        ciContext.render(processedImage, to: outputPixelBuffer)
        request.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    private func applyFaceBlur(to image: CIImage) -> CIImage {
        guard let detector = faceDetector else { return image }
        let faces = detector.features(in: image) as? [CIFaceFeature] ?? []
        var outputImage = image
        for face in faces {
            let blurArea = face.bounds.insetBy(dx: -15, dy: -15)
            let blurFilter = CIFilter(name: "CIGaussianBlur")!
            blurFilter.setValue(image.cropped(to: blurArea), forKey: kCIInputImageKey)
            blurFilter.setValue(15.0, forKey: kCIInputRadiusKey)
            guard let blurredRegion = blurFilter.outputImage else { continue }
            let composite = CIFilter(name: "CISourceOverCompositing")!
            composite.setValue(blurredRegion, forKey: kCIInputImageKey)
            composite.setValue(outputImage, forKey: kCIInputBackgroundImageKey)
            if let result = composite.outputImage {
                outputImage = result
            }
        }
        return outputImage
    }
} 