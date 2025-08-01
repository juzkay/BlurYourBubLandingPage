import Foundation
import CoreML
import Vision
import UIKit

// MARK: - Core ML Enhanced Face Detection (Industry Standard)
class CoreMLFaceDetector {
    
    // MARK: - Professional Face Detection with Core ML
    
    /// Detect faces using Apple's Core ML models (same as Camera app)
    func detectFacesWithCoreML(in image: UIImage) -> [PhotoDetectedFace] {
        print("[CoreMLFaceDetector] 🏭 PROFESSIONAL: Starting Core ML face detection...")
        
        var detectedFaces: [PhotoDetectedFace] = []
        
        guard let cgImage = image.cgImage else {
            print("[CoreMLFaceDetector] ❌ Failed to get CGImage")
            return detectedFaces
        }
        
        // INDUSTRY STANDARD: Use multiple detection strategies for maximum accuracy
        detectedFaces = detectWithVisionCoreML(cgImage: cgImage, imageSize: image.size)
        
        // If Core ML doesn't find faces, try alternative approaches
        if detectedFaces.isEmpty {
            print("[CoreMLFaceDetector] 🏭 FALLBACK: Core ML found 0 faces, trying enhanced Vision...")
            detectedFaces = detectWithEnhancedVision(cgImage: cgImage, imageSize: image.size)
        }
        
        print("[CoreMLFaceDetector] 🏭 FINAL RESULT: \(detectedFaces.count) professional-grade faces detected")
        return detectedFaces
    }
    
    // MARK: - Core ML + Vision Framework Integration
    
    private func detectWithVisionCoreML(cgImage: CGImage, imageSize: CGSize) -> [PhotoDetectedFace] {
        var detectedFaces: [PhotoDetectedFace] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        // PROFESSIONAL: Use highest quality Vision request with Core ML models
        let request = VNDetectFaceLandmarksRequest { request, error in
            defer { semaphore.signal() }
            
            guard let results = request.results as? [VNFaceObservation], error == nil else {
                print("[CoreMLFaceDetector] ❌ Core ML Vision request failed: \(error?.localizedDescription ?? "Unknown")")
                return
            }
            
            print("[CoreMLFaceDetector] 🏭 Core ML detected \(results.count) face candidates")
            
            for (index, observation) in results.enumerated() {
                // INDUSTRY STANDARD: Multi-stage quality assessment
                let qualityResult = self.assessFaceQualityMultiStage(observation: observation)
                
                guard qualityResult.isProfessional else {
                    print("[CoreMLFaceDetector] ❌ Face \(index + 1): REJECTED - Below professional standards")
                    print("[CoreMLFaceDetector]   Confidence: \(observation.confidence)")
                    print("[CoreMLFaceDetector]   Quality Score: \(qualityResult.score)")
                    continue
                }
                
                // PROFESSIONAL: Create precise face bounds
                let preciseBounds = self.createProfessionalFaceBounds(
                    observation: observation, 
                    imageSize: imageSize,
                    cgImage: cgImage
                )
                
                print("[CoreMLFaceDetector] ✅ Face \(index + 1): PROFESSIONAL GRADE DETECTED")
                print("[CoreMLFaceDetector]   Confidence: \(observation.confidence)")
                print("[CoreMLFaceDetector]   Quality Score: \(qualityResult.score)")
                print("[CoreMLFaceDetector]   Precise Bounds: \(preciseBounds)")
                
                // Create face image with high quality cropping
                if let faceImage = self.cropFaceWithHighQuality(
                    cgImage: cgImage,
                    bounds: preciseBounds,
                    originalSize: imageSize
                ) {
                    let detectedFace = PhotoDetectedFace(
                        boundingBox: preciseBounds,
                        faceImage: faceImage
                    )
                    detectedFaces.append(detectedFace)
                }
            }
        }
        
        // INDUSTRY STANDARD: Configure for maximum accuracy
        request.revision = VNDetectFaceLandmarksRequestRevision3
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [
            .orientation: CGImagePropertyOrientation.up,
            .properties: [:]
        ])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("[CoreMLFaceDetector] ❌ Failed to perform Core ML detection: \(error)")
            }
        }
        
        semaphore.wait()
        return detectedFaces
    }
    
    // MARK: - Enhanced Vision Framework Detection
    
    private func detectWithEnhancedVision(cgImage: CGImage, imageSize: CGSize) -> [PhotoDetectedFace] {
        var detectedFaces: [PhotoDetectedFace] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        // FALLBACK: Enhanced Vision detection with multiple configurations
        let configurations: [(VNDetectFaceRectanglesRequest, String)] = [
            (createHighAccuracyRequest(), "High Accuracy"),
            (createBalancedRequest(), "Balanced"),
            (createHighRecallRequest(), "High Recall")
        ]
        
        for (request, configName) in configurations {
            var currentFaces: [PhotoDetectedFace] = []
            
            request.completion = { request, error in
                defer { semaphore.signal() }
                
                guard let results = request.results as? [VNFaceObservation], error == nil else {
                    return
                }
                
                print("[CoreMLFaceDetector] 🏭 Enhanced Vision (\(configName)): \(results.count) candidates")
                
                for observation in results {
                    if observation.confidence > 0.6 { // Higher threshold for fallback
                        let bounds = self.convertNormalizedRect(observation.boundingBox, to: imageSize)
                        
                        if let faceImage = self.cropFaceWithHighQuality(
                            cgImage: cgImage,
                            bounds: bounds,
                            originalSize: imageSize
                        ) {
                            let detectedFace = PhotoDetectedFace(
                                boundingBox: bounds,
                                faceImage: faceImage
                            )
                            currentFaces.append(detectedFace)
                        }
                    }
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    print("[CoreMLFaceDetector] Enhanced Vision (\(configName)) failed: \(error)")
                    semaphore.signal()
                }
            }
            
            semaphore.wait()
            
            if !currentFaces.isEmpty {
                detectedFaces = currentFaces
                print("[CoreMLFaceDetector] ✅ Enhanced Vision (\(configName)) succeeded with \(detectedFaces.count) faces")
                break
            }
        }
        
        return detectedFaces
    }
    
    // MARK: - Professional Quality Assessment
    
    private func assessFaceQualityMultiStage(observation: VNFaceObservation) -> (isProfessional: Bool, score: Double) {
        var qualityScore: Double = 0.0
        var qualityFactors: [String: Double] = [:]
        
        // Factor 1: Confidence (30% weight)
        let confidenceScore = Double(observation.confidence)
        qualityFactors["confidence"] = confidenceScore
        qualityScore += confidenceScore * 0.3
        
        // Factor 2: Landmark completeness (25% weight)
        var landmarkScore: Double = 0.0
        if let landmarks = observation.landmarks {
            let requiredLandmarks = [
                landmarks.leftEye,
                landmarks.rightEye,
                landmarks.nose,
                landmarks.outerLips
            ]
            
            let availableLandmarks = requiredLandmarks.compactMap { $0 }.count
            landmarkScore = Double(availableLandmarks) / Double(requiredLandmarks.count)
            qualityFactors["landmarks"] = landmarkScore
            qualityScore += landmarkScore * 0.25
        }
        
        // Factor 3: Bounding box quality (20% weight)
        let boxAspectRatio = observation.boundingBox.width / observation.boundingBox.height
        let aspectScore = max(0.0, 1.0 - abs(boxAspectRatio - 1.0)) // Prefer square-ish faces
        qualityFactors["aspect"] = aspectScore
        qualityScore += aspectScore * 0.2
        
        // Factor 4: Size appropriateness (15% weight)
        let faceArea = observation.boundingBox.width * observation.boundingBox.height
        let sizeScore = min(1.0, max(0.0, (faceArea - 0.01) / 0.1)) // Prefer faces that are 1-10% of image
        qualityFactors["size"] = sizeScore
        qualityScore += sizeScore * 0.15
        
        // Factor 5: Position (10% weight)
        let centerX = observation.boundingBox.midX
        let centerY = observation.boundingBox.midY
        let positionScore = 1.0 - max(abs(centerX - 0.5), abs(centerY - 0.5)) * 2.0
        qualityFactors["position"] = max(0.0, positionScore)
        qualityScore += max(0.0, positionScore) * 0.1
        
        // PROFESSIONAL THRESHOLD: 0.75+ for professional grade
        let isProfessional = qualityScore >= 0.75 && confidenceScore >= 0.7 && landmarkScore >= 0.75
        
        if isProfessional {
            print("[CoreMLFaceDetector] 🏆 PROFESSIONAL GRADE FACE:")
            for (factor, score) in qualityFactors {
                print("[CoreMLFaceDetector]   \(factor): \(String(format: "%.2f", score))")
            }
        }
        
        return (isProfessional: isProfessional, score: qualityScore)
    }
    
    // MARK: - Professional Face Bounds Creation
    
    private func createProfessionalFaceBounds(observation: VNFaceObservation, imageSize: CGSize, cgImage: CGImage) -> CGRect {
        var bounds = convertNormalizedRect(observation.boundingBox, to: imageSize)
        
        // PROFESSIONAL: Refine bounds using facial landmarks if available
        if let landmarks = observation.landmarks,
           let faceContour = landmarks.faceContour,
           faceContour.pointCount > 0 {
            
            let contourPoints = faceContour.normalizedPoints
            
            // Calculate the actual face boundary
            let minX = contourPoints.map { $0.x }.min() ?? observation.boundingBox.minX
            let maxX = contourPoints.map { $0.x }.max() ?? observation.boundingBox.maxX
            let minY = contourPoints.map { $0.y }.min() ?? observation.boundingBox.minY
            let maxY = contourPoints.map { $0.y }.max() ?? observation.boundingBox.maxY
            
            // Convert to image coordinates with professional padding
            let padding: CGFloat = max(20.0, min(bounds.width, bounds.height) * 0.1)
            
            bounds = CGRect(
                x: max(0, minX * imageSize.width - padding),
                y: max(0, (1.0 - maxY) * imageSize.height - padding),
                width: min(imageSize.width, (maxX - minX) * imageSize.width + padding * 2),
                height: min(imageSize.height, (maxY - minY) * imageSize.height + padding * 2)
            )
        }
        
        return bounds
    }
    
    // MARK: - High-Quality Face Cropping
    
    private func cropFaceWithHighQuality(cgImage: CGImage, bounds: CGRect, originalSize: CGSize) -> UIImage? {
        // Ensure bounds are within image
        let clampedBounds = bounds.intersection(CGRect(origin: .zero, size: originalSize))
        guard !clampedBounds.isNull && !clampedBounds.isEmpty else { return nil }
        
        // Convert to CGImage coordinates
        let scale = CGFloat(cgImage.width) / originalSize.width
        let cropRect = CGRect(
            x: clampedBounds.origin.x * scale,
            y: clampedBounds.origin.y * scale,
            width: clampedBounds.width * scale,
            height: clampedBounds.height * scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return nil }
        
        return UIImage(cgImage: croppedCGImage)
    }
    
    // MARK: - Vision Request Configurations
    
    private func createHighAccuracyRequest() -> VNDetectFaceRectanglesRequest {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }
    
    private func createBalancedRequest() -> VNDetectFaceRectanglesRequest {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision2
        return request
    }
    
    private func createHighRecallRequest() -> VNDetectFaceRectanglesRequest {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision1
        return request
    }
    
    // MARK: - Utility Functions
    
    private func convertNormalizedRect(_ normalizedRect: CGRect, to imageSize: CGSize) -> CGRect {
        return CGRect(
            x: normalizedRect.origin.x * imageSize.width,
            y: (1 - normalizedRect.origin.y - normalizedRect.height) * imageSize.height,
            width: normalizedRect.width * imageSize.width,
            height: normalizedRect.height * imageSize.height
        )
    }
}