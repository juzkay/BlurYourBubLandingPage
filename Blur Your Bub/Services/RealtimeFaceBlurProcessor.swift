import Foundation
import CoreImage

class RealtimeFaceBlurProcessor {
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var faceDetector: CIDetector?
    
    init() {
        setupFaceDetector()
    }
    
    private func setupFaceDetector() {
        faceDetector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: ciContext,
            options: [
                CIDetectorAccuracy: CIDetectorAccuracyHigh,
                CIDetectorTracking: true
            ]
        )
    }
    
    func processFrame(_ pixelBuffer: CVPixelBuffer, shouldBlur: Bool) -> CVPixelBuffer {
        guard shouldBlur else { return pixelBuffer }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let processedImage = applyFaceBlur(to: ciImage)
        // Render back to pixel buffer
        ciContext.render(processedImage, to: pixelBuffer)
        return pixelBuffer
    }
    
    private func applyFaceBlur(to image: CIImage) -> CIImage {
        guard let detector = faceDetector else { return image }
        let faces = detector.features(in: image) as? [CIFaceFeature] ?? []
        var outputImage = image
        for face in faces {
            // Create a slightly larger blur area
            let blurArea = face.bounds.insetBy(dx: -10, dy: -10)
            // Apply Gaussian blur
            let blurFilter = CIFilter(name: "CIGaussianBlur")!
            blurFilter.setValue(image.cropped(to: blurArea), forKey: kCIInputImageKey)
            blurFilter.setValue(12.0, forKey: kCIInputRadiusKey)
            guard let blurredRegion = blurFilter.outputImage else { continue }
            // Composite back onto original
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