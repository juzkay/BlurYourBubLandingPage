import Foundation
import CoreImage
import UIKit
import Vision

class PhotoFaceDetector {
    
    func detectFaces(in image: UIImage) -> [PhotoDetectedFace] {
        // Convert UIImage to CIImage for Vision framework
        guard let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)
        
        var detectedFaces: [PhotoDetectedFace] = []
        
        // Create face detection request with high accuracy
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
            guard let results = request.results as? [VNFaceObservation], error == nil else {
                print("[PhotoFaceDetector] Face detection failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            print("[PhotoFaceDetector] Detected \(results.count) faces")
            
            // Convert Vision results to our model
            for (index, faceObservation) in results.enumerated() {
                // Convert normalized coordinates to image coordinates
                let imageSize = image.size
                let boundingBox = self.convertNormalizedRect(
                    faceObservation.boundingBox,
                    to: imageSize
                )
                
                print("[PhotoFaceDetector] Face \(index): confidence=\(faceObservation.confidence), bounds=\(boundingBox)")
                
                // Only include faces with reasonable confidence
                if faceObservation.confidence > 0.5 {
                    let faceImage = self.cropFaceFromImage(image: image, boundingBox: boundingBox)
                    let detectedFace = PhotoDetectedFace(boundingBox: boundingBox, faceImage: faceImage)
                    detectedFaces.append(detectedFace)
                }
            }
        }
        
        // Configure detection for better accuracy
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3 // Latest revision
        
        // Perform the detection
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            print("[PhotoFaceDetector] Vision request failed: \(error.localizedDescription)")
        }
        
        return detectedFaces
    }
    
    // Enhanced face detection with landmarks for more precise boundaries
    func detectFacesWithLandmarks(in image: UIImage) -> [PhotoDetectedFace] {
        guard let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)
        
        var detectedFaces: [PhotoDetectedFace] = []
        
        // Use face landmarks for more precise detection
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { request, error in
            guard let results = request.results as? [VNFaceObservation], error == nil else {
                print("[PhotoFaceDetector] Face landmarks detection failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            print("[PhotoFaceDetector] Detected \(results.count) faces with landmarks")
            
            for (index, faceObservation) in results.enumerated() {
                let imageSize = image.size
                var boundingBox = self.convertNormalizedRect(faceObservation.boundingBox, to: imageSize)
                
                // If we have landmarks, use them to create a more precise bounding box
                if let landmarks = faceObservation.landmarks {
                    boundingBox = self.enhancedBoundingBox(
                        from: landmarks,
                        originalBox: boundingBox,
                        imageSize: imageSize
                    )
                }
                
                print("[PhotoFaceDetector] Enhanced face \(index): confidence=\(faceObservation.confidence), bounds=\(boundingBox)")
                
                // Lower confidence threshold since landmarks provide additional validation
                if faceObservation.confidence > 0.3 {
                    let faceImage = self.cropFaceFromImage(image: image, boundingBox: boundingBox)
                    let detectedFace = PhotoDetectedFace(boundingBox: boundingBox, faceImage: faceImage)
                    detectedFaces.append(detectedFace)
                }
            }
        }
        
        // Configure for best accuracy
        faceLandmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
        
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([faceLandmarksRequest])
        } catch {
            print("[PhotoFaceDetector] Vision landmarks request failed: \(error.localizedDescription)")
            // Fallback to basic face detection
            return detectFaces(in: image)
        }
        
        return detectedFaces
    }
    
    // Aggressive face detection for challenging lighting/angles
    func detectFacesAggressive(in image: UIImage) -> [PhotoDetectedFace] {
        guard let cgImage = image.cgImage else { return [] }
        
        // Try preprocessing the image to improve detection
        let preprocessedImage = preprocessImageForDetection(image: image)
        let ciImage = CIImage(cgImage: preprocessedImage.cgImage ?? cgImage)
        
        var detectedFaces: [PhotoDetectedFace] = []
        
        // Use the most aggressive settings for difficult photos
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
            guard let results = request.results as? [VNFaceObservation], error == nil else {
                print("[PhotoFaceDetector] Aggressive face detection failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            print("[PhotoFaceDetector] Aggressive detection found \(results.count) faces")
            
            for (index, faceObservation) in results.enumerated() {
                let imageSize = image.size
                let boundingBox = self.convertNormalizedRect(
                    faceObservation.boundingBox,
                    to: imageSize
                )
                
                print("[PhotoFaceDetector] Aggressive face \(index): confidence=\(faceObservation.confidence), bounds=\(boundingBox)")
                
                // Very low confidence threshold for challenging photos
                if faceObservation.confidence > 0.1 {
                    let faceImage = self.cropFaceFromImage(image: image, boundingBox: boundingBox)
                    let detectedFace = PhotoDetectedFace(boundingBox: boundingBox, faceImage: faceImage)
                    detectedFaces.append(detectedFace)
                }
            }
        }
        
        // Use latest revision with custom options for challenging conditions
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3
        
        // Enhanced options for difficult detection scenarios
        let options: [VNImageOption: Any] = [:]
        let handler = VNImageRequestHandler(ciImage: ciImage, options: options)
        
        do {
            try handler.perform([faceDetectionRequest])
        } catch {
            print("[PhotoFaceDetector] Aggressive Vision request failed: \(error.localizedDescription)")
        }
        
        return detectedFaces
    }
    
    // Convert Vision's normalized coordinates to image pixel coordinates
    private func convertNormalizedRect(_ normalizedRect: CGRect, to imageSize: CGSize) -> CGRect {
        // Vision uses bottom-left origin, UIKit uses top-left origin
        let x = normalizedRect.origin.x * imageSize.width
        let y = (1 - normalizedRect.origin.y - normalizedRect.height) * imageSize.height
        let width = normalizedRect.width * imageSize.width
        let height = normalizedRect.height * imageSize.height
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    // Create enhanced bounding box using face landmarks
    private func enhancedBoundingBox(from landmarks: VNFaceLandmarks2D, originalBox: CGRect, imageSize: CGSize) -> CGRect {
        var minX = originalBox.maxX
        var maxX = originalBox.minX
        var minY = originalBox.maxY
        var maxY = originalBox.minY
        
        // Check various landmark regions to expand the bounding box
        let landmarkRegions: [VNFaceLandmarkRegion2D?] = [
            landmarks.faceContour,
            landmarks.leftEye,
            landmarks.rightEye,
            landmarks.nose,
            landmarks.outerLips,
            landmarks.leftEyebrow,
            landmarks.rightEyebrow
        ]
        
        for region in landmarkRegions {
            guard let region = region else { continue }
            
            for i in 0..<region.pointCount {
                let point = region.normalizedPoints[i]
                let imagePoint = CGPoint(
                    x: point.x * originalBox.width + originalBox.minX,
                    y: point.y * originalBox.height + originalBox.minY
                )
                
                minX = min(minX, imagePoint.x)
                maxX = max(maxX, imagePoint.x)
                minY = min(minY, imagePoint.y)
                maxY = max(maxY, imagePoint.y)
            }
        }
        
        // Add some padding around the landmarks
        let padding: CGFloat = 20
        return CGRect(
            x: max(0, minX - padding),
            y: max(0, minY - padding),
            width: min(imageSize.width - max(0, minX - padding), maxX - minX + 2 * padding),
            height: min(imageSize.height - max(0, minY - padding), maxY - minY + 2 * padding)
        )
    }
    
    // Preprocess image to improve face detection in challenging conditions
    private func preprocessImageForDetection(image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()
        
        // Apply contrast and brightness adjustments to help with dark/low contrast photos
        let contrastFilter = CIFilter(name: "CIColorControls")!
        contrastFilter.setValuesForKeys([
            kCIInputImageKey: ciImage,
            "inputContrast": 1.2,      // Increase contrast
            "inputBrightness": 0.1,    // Slightly brighten
            "inputSaturation": 1.1     // Slightly increase saturation
        ])
        
        // Apply exposure adjustment for very dark images
        let exposureFilter = CIFilter(name: "CIExposureAdjust")!
        exposureFilter.setValuesForKeys([
            kCIInputImageKey: contrastFilter.outputImage!,
            "inputEV": 0.5  // Increase exposure slightly
        ])
        
        // Sharpen the image to enhance facial features
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")!
        sharpenFilter.setValuesForKeys([
            kCIInputImageKey: exposureFilter.outputImage!,
            "inputSharpness": 0.7
        ])
        
        guard let outputImage = sharpenFilter.outputImage,
              let processedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            print("[PhotoFaceDetector] Image preprocessing failed, using original")
            return image
        }
        
        print("[PhotoFaceDetector] Image preprocessed for better detection")
        return UIImage(cgImage: processedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
    
    private func cropFaceFromImage(image: UIImage, boundingBox: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        // Ensure the bounding box is within image bounds
        let imageBounds = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height)
        let clampedBox = boundingBox.intersection(imageBounds)
        
        guard !clampedBox.isNull && !clampedBox.isEmpty else { return nil }
        
        // Crop the image
        guard let croppedCGImage = cgImage.cropping(to: clampedBox) else { return nil }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}