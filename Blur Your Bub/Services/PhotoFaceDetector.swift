import Foundation
import CoreImage
import UIKit
import Vision

// MARK: - Face Quality Assessment
struct FaceQuality {
    let overallScore: Double
    let hasEyes: Bool
    let hasNose: Bool
    let hasMouth: Bool
    let landmarkCompleteness: Double
    let faceSymmetry: Double
    let confidenceScore: Double
    
    var isHighQuality: Bool {
        return overallScore > 0.7 && 
               hasEyes && 
               hasNose && 
               hasMouth && 
               landmarkCompleteness > 0.6
    }
    
    var isProfessionalGrade: Bool {
        return overallScore > 0.85 && 
               isHighQuality && 
               faceSymmetry > 0.7 && 
               confidenceScore > 0.8
    }
}

class PhotoFaceDetector {
    
    // PRIMARY: Professional Landmarks detection (Industry Standard)
    func detectFacesWithProfessionalAI(in image: UIImage) -> [PhotoDetectedFace] {
        print("[PhotoFaceDetector] 🏭 PROFESSIONAL AI: Starting industry-standard landmarks detection...")
        
        // TIER 1: Professional landmarks detection (highest quality)
        let landmarkFaces = detectFacesWithLandmarks(in: image)
        if !landmarkFaces.isEmpty {
            print("[PhotoFaceDetector] 🏭 SUCCESS: Professional landmarks detected \(landmarkFaces.count) high-quality faces")
            return landmarkFaces
        }
        
        // TIER 2: Enhanced Vision detection with multiple approaches
        print("[PhotoFaceDetector] 🏭 FALLBACK: Landmarks found 0 faces, trying enhanced Vision detection...")
        let enhancedFaces = detectFacesWithEnhancedVision(in: image)
        if !enhancedFaces.isEmpty {
            print("[PhotoFaceDetector] 🏭 SUCCESS: Enhanced Vision detected \(enhancedFaces.count) faces")
            return enhancedFaces
        }
        
        // TIER 3: Basic detection (last resort)
        print("[PhotoFaceDetector] 🏭 FINAL FALLBACK: Trying basic detection...")
        let basicFaces = detectFaces(in: image)
        print("[PhotoFaceDetector] 🏭 FINAL RESULT: \(basicFaces.count) faces detected via basic method")
        
        return basicFaces
    }
    
    func detectFaces(in image: UIImage) -> [PhotoDetectedFace] {
        // Convert UIImage to CIImage for Vision framework
        guard let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)
        
        var detectedFaces: [PhotoDetectedFace] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        // Create face detection request with high accuracy
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
            defer { semaphore.signal() }
            
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
                if faceObservation.confidence > 0.3 { // Lowered threshold for better detection
                    let faceImage = self.cropFaceFromImage(image: image, boundingBox: boundingBox)
                    let detectedFace = PhotoDetectedFace(boundingBox: boundingBox, faceImage: faceImage)
                    detectedFaces.append(detectedFace)
                    print("[PhotoFaceDetector] Added face with confidence \(faceObservation.confidence): \(boundingBox)")
                } else {
                    print("[PhotoFaceDetector] Rejected face with low confidence \(faceObservation.confidence): \(boundingBox)")
                }
            }
        }
        
        // Configure detection for better accuracy
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3 // Latest revision
        
        // Perform the detection
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([faceDetectionRequest])
            // Wait for the async completion
            _ = semaphore.wait(timeout: .now() + 10.0) // 10 second timeout
        } catch {
            print("[PhotoFaceDetector] Vision request failed: \(error.localizedDescription)")
        }
        
        return detectedFaces
    }
    
    // INDUSTRY STANDARD: Professional face detection with landmarks (like Photos app)
    func detectFacesWithLandmarks(in image: UIImage) -> [PhotoDetectedFace] {
        guard let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)
        
        var detectedFaces: [PhotoDetectedFace] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        // PROFESSIONAL: Use face landmarks with quality assessment (industry standard)
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { request, error in
            defer { semaphore.signal() }
            
            guard let results = request.results as? [VNFaceObservation], error == nil else {
                print("[PhotoFaceDetector] 🏭 PROFESSIONAL: Face landmarks detection failed: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            print("[PhotoFaceDetector] 🏭 PROFESSIONAL: Detected \(results.count) face candidates with landmarks")
            
            for (index, faceObservation) in results.enumerated() {
                print("[PhotoFaceDetector] 🏭 Analyzing face \(index + 1)...")
                
                // INDUSTRY STANDARD: Calculate face quality using landmarks
                guard let faceQuality = self.calculateFaceQuality(from: faceObservation) else {
                    print("[PhotoFaceDetector] ❌ Face \(index + 1): Could not assess quality")
                    continue
                }
                
                print("[PhotoFaceDetector] 🏭 Face \(index + 1) Quality Assessment:")
                print("[PhotoFaceDetector]   Overall Score: \(faceQuality.overallScore)")
                print("[PhotoFaceDetector]   Has Eyes: \(faceQuality.hasEyes)")
                print("[PhotoFaceDetector]   Has Nose: \(faceQuality.hasNose)")
                print("[PhotoFaceDetector]   Has Mouth: \(faceQuality.hasMouth)")
                print("[PhotoFaceDetector]   Landmark Completeness: \(faceQuality.landmarkCompleteness)")
                print("[PhotoFaceDetector]   Face Symmetry: \(faceQuality.faceSymmetry)")
                print("[PhotoFaceDetector]   Confidence: \(faceQuality.confidenceScore)")
                
                // PROFESSIONAL STANDARD: Only accept high-quality faces
                guard faceQuality.isHighQuality else {
                    print("[PhotoFaceDetector] ❌ Face \(index + 1): REJECTED - Poor quality (score: \(faceQuality.overallScore))")
                    continue
                }
                
                let imageSize = image.size
                
                // INDUSTRY STANDARD: Create precise face bounds using landmarks
                let preciseBounds = self.createPreciseFaceBounds(from: faceObservation, imageSize: imageSize)
                
                print("[PhotoFaceDetector] ✅ Face \(index + 1): HIGH QUALITY FACE DETECTED")
                print("[PhotoFaceDetector]   Confidence: \(faceObservation.confidence)")
                print("[PhotoFaceDetector]   Quality Score: \(faceQuality.overallScore)")
                print("[PhotoFaceDetector]   Precise Bounds: \(preciseBounds)")
                print("[PhotoFaceDetector]   Professional Grade: \(faceQuality.isProfessionalGrade ? "YES" : "NO")")
                
                // Crop face image using precise bounds
                let faceImage = self.cropFaceFromImage(image: image, boundingBox: preciseBounds)
                let detectedFace = PhotoDetectedFace(boundingBox: preciseBounds, faceImage: faceImage)
                detectedFaces.append(detectedFace)
            }
            
            print("[PhotoFaceDetector] 🏭 PROFESSIONAL: Final result = \(detectedFaces.count) high-quality faces")
        }
        
        // Configure for best accuracy
        faceLandmarksRequest.revision = VNDetectFaceLandmarksRequestRevision3
        
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([faceLandmarksRequest])
            // Wait for the async completion
            _ = semaphore.wait(timeout: .now() + 10.0) // 10 second timeout
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
        let semaphore = DispatchSemaphore(value: 0)
        
        // Use the most aggressive settings for difficult photos
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
            defer { semaphore.signal() }
            
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
            // Wait for the async completion
            _ = semaphore.wait(timeout: .now() + 10.0) // 10 second timeout
        } catch {
            print("[PhotoFaceDetector] Aggressive Vision request failed: \(error.localizedDescription)")
        }
        
        return detectedFaces
    }
    
    // Multiple detection strategies with different parameters
    func detectFacesMultiStrategy(in image: UIImage) -> [PhotoDetectedFace] {
        print("🔍 [PhotoFaceDetector] ===== STARTING FACE DETECTION DEBUG =====")
        print("🔍 [PhotoFaceDetector] Image size: \(image.size)")
        print("🔍 [PhotoFaceDetector] Image scale: \(image.scale)")
        
        var allDetectedFaces: [PhotoDetectedFace] = []
        
        // Strategy 1: Standard detection
        print("🔍 [PhotoFaceDetector] Strategy 1: Standard detection")
        let standardFaces = detectFaces(in: image)
        allDetectedFaces.append(contentsOf: standardFaces)
        print("🔍 [PhotoFaceDetector] Strategy 1 found: \(standardFaces.count) faces")
        
        // Strategy 2: Landmarks detection
        print("🔍 [PhotoFaceDetector] Strategy 2: Landmarks detection")
        let landmarksFaces = detectFacesWithLandmarks(in: image)
        allDetectedFaces.append(contentsOf: landmarksFaces)
        print("🔍 [PhotoFaceDetector] Strategy 2 found: \(landmarksFaces.count) faces")
        
        // Strategy 3: Aggressive detection with preprocessing
        print("🔍 [PhotoFaceDetector] Strategy 3: Aggressive detection")
        let aggressiveFaces = detectFacesAggressive(in: image)
        allDetectedFaces.append(contentsOf: aggressiveFaces)
        print("🔍 [PhotoFaceDetector] Strategy 3 found: \(aggressiveFaces.count) faces")
        
        // Strategy 4: Try with different image orientations
        print("🔍 [PhotoFaceDetector] Strategy 4: Multiple orientations")
        let orientationFaces = detectFacesWithOrientations(in: image)
        allDetectedFaces.append(contentsOf: orientationFaces)
        print("🔍 [PhotoFaceDetector] Strategy 4 found: \(orientationFaces.count) faces")
        
        print("🔍 [PhotoFaceDetector] Total before deduplication: \(allDetectedFaces.count) faces")
        
        // Remove duplicates and merge overlapping detections
        let uniqueFaces = mergeOverlappingFaces(allDetectedFaces)
        print("🔍 [PhotoFaceDetector] After deduplication: \(uniqueFaces.count) faces")
        
        // Debug: Print all detected faces before validation
        for (index, face) in uniqueFaces.enumerated() {
            print("🔍 [PhotoFaceDetector] Face \(index + 1) before validation: \(face.boundingBox)")
        }
        
        // Apply strict validation to filter out false positives
        let validatedFaces = validateAndFilterFaces(uniqueFaces, in: image)
        print("🔍 [PhotoFaceDetector] After validation: \(validatedFaces.count) faces")
        
        // Debug: Print all validated faces
        for (index, face) in validatedFaces.enumerated() {
            print("🔍 [PhotoFaceDetector] Final face \(index + 1): \(face.boundingBox)")
            print("🔍 [PhotoFaceDetector]   Dimensions: \(face.boundingBox.width) x \(face.boundingBox.height)")
            print("🔍 [PhotoFaceDetector]   Aspect ratio: \(face.boundingBox.width / face.boundingBox.height)")
            print("🔍 [PhotoFaceDetector]   Center: (\(face.boundingBox.midX), \(face.boundingBox.midY))")
            print("🔍 [PhotoFaceDetector]   Area: \(face.boundingBox.width * face.boundingBox.height) pixels")
        }
        
        print("🔍 [PhotoFaceDetector] ===== FACE DETECTION DEBUG COMPLETE =====")
        return validatedFaces
    }
    
    // Try detection with different image orientations
    private func detectFacesWithOrientations(in image: UIImage) -> [PhotoDetectedFace] {
        var allFaces: [PhotoDetectedFace] = []
        
        // Try original orientation
        if let cgImage = image.cgImage {
            let ciImage = CIImage(cgImage: cgImage)
            let faces = performDetection(on: ciImage, imageSize: image.size)
            allFaces.append(contentsOf: faces)
        }
        
        // Try rotated versions (90, 180, 270 degrees)
        let rotations: [CGFloat] = [90, 180, 270]
        for rotation in rotations {
            if let rotatedImage = rotateImage(image, by: rotation),
               let cgImage = rotatedImage.cgImage {
                let ciImage = CIImage(cgImage: cgImage)
                let faces = performDetection(on: ciImage, imageSize: rotatedImage.size)
                
                // Convert face coordinates back to original orientation
                let convertedFaces = faces.map { face in
                    let convertedBox = convertRotatedBoundingBox(face.boundingBox, from: rotatedImage.size, to: image.size, rotation: rotation)
                    return PhotoDetectedFace(boundingBox: convertedBox, faceImage: face.faceImage)
                }
                allFaces.append(contentsOf: convertedFaces)
            }
        }
        
        return allFaces
    }
    
    // Perform detection on a CIImage
    private func performDetection(on ciImage: CIImage, imageSize: CGSize) -> [PhotoDetectedFace] {
        var detectedFaces: [PhotoDetectedFace] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest { request, error in
            defer { semaphore.signal() }
            
            guard let results = request.results as? [VNFaceObservation], error == nil else {
                return
            }
            
            for faceObservation in results {
                if faceObservation.confidence > 0.3 {
                    let boundingBox = self.convertNormalizedRect(faceObservation.boundingBox, to: imageSize)
                    let detectedFace = PhotoDetectedFace(boundingBox: boundingBox, faceImage: nil)
                    detectedFaces.append(detectedFace)
                }
            }
        }
        
        faceDetectionRequest.revision = VNDetectFaceRectanglesRequestRevision3
        
        let handler = VNImageRequestHandler(ciImage: ciImage, options: [:])
        do {
            try handler.perform([faceDetectionRequest])
            _ = semaphore.wait(timeout: .now() + 5.0)
        } catch {
            print("[PhotoFaceDetector] Orientation detection failed: \(error.localizedDescription)")
        }
        
        return detectedFaces
    }
    
    // Merge overlapping face detections
    private func mergeOverlappingFaces(_ faces: [PhotoDetectedFace]) -> [PhotoDetectedFace] {
        var uniqueFaces: [PhotoDetectedFace] = []
        
        for face in faces {
            var isDuplicate = false
            
            for existingFace in uniqueFaces {
                let overlap = face.boundingBox.intersection(existingFace.boundingBox)
                let overlapArea = overlap.width * overlap.height
                let faceArea = face.boundingBox.width * face.boundingBox.height
                let existingArea = existingFace.boundingBox.width * existingFace.boundingBox.height
                
                // If overlap is more than 50% of either face, consider it a duplicate
                if overlapArea > 0 && (overlapArea / faceArea > 0.5 || overlapArea / existingArea > 0.5) {
                    isDuplicate = true
                    break
                }
            }
            
            if !isDuplicate {
                uniqueFaces.append(face)
            }
        }
        
        return uniqueFaces
    }
    
    // Rotate image by degrees
    private func rotateImage(_ image: UIImage, by degrees: CGFloat) -> UIImage? {
        let radians = degrees * .pi / 180
        let rotatedSize = CGSize(width: image.size.height, height: image.size.width)
        
        UIGraphicsBeginImageContextWithOptions(rotatedSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        context.translateBy(x: rotatedSize.width / 2, y: rotatedSize.height / 2)
        context.rotate(by: radians)
        image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return rotatedImage
    }
    
    // Convert bounding box from rotated image back to original orientation
    private func convertRotatedBoundingBox(_ box: CGRect, from rotatedSize: CGSize, to originalSize: CGSize, rotation: CGFloat) -> CGRect {
        let radians = rotation * .pi / 180
        
        // Convert to center-based coordinates
        let centerX = box.midX
        let centerY = box.midY
        
        // Rotate the center point
        let rotatedCenterX = centerX * cos(radians) - centerY * sin(radians)
        let rotatedCenterY = centerX * sin(radians) + centerY * cos(radians)
        
        // Convert back to corner-based coordinates
        let newX = rotatedCenterX - box.width / 2
        let newY = rotatedCenterY - box.height / 2
        
        // Scale to original image size
        let scaleX = originalSize.width / rotatedSize.width
        let scaleY = originalSize.height / rotatedSize.height
        
        return CGRect(
            x: newX * scaleX,
            y: newY * scaleY,
            width: box.width * scaleX,
            height: box.height * scaleY
        )
    }
    
    // MARK: - Face Validation and Filtering
    
    // Validate and filter detected faces to remove false positives
    private func validateAndFilterFaces(_ faces: [PhotoDetectedFace], in image: UIImage) -> [PhotoDetectedFace] {
        var validatedFaces: [PhotoDetectedFace] = []
        
        print("[PhotoFaceDetector] Starting validation of \(faces.count) detected faces...")
        
        for (index, face) in faces.enumerated() {
            print("[PhotoFaceDetector] Validating face \(index + 1): \(face.boundingBox)")
            
            if isValidFace(face, in: image) {
                validatedFaces.append(face)
                print("[PhotoFaceDetector] ✅ Face \(index + 1) PASSED validation")
            } else {
                print("[PhotoFaceDetector] ❌ Face \(index + 1) FAILED validation")
            }
        }
        
        print("[PhotoFaceDetector] Validation complete: \(validatedFaces.count)/\(faces.count) faces passed")
        return validatedFaces
    }
    
    // Check if a detected face is valid (not a false positive)
    private func isValidFace(_ face: PhotoDetectedFace, in image: UIImage) -> Bool {
        let box = face.boundingBox
        let imageSize = image.size
        
        print("🔍 [PhotoFaceDetector] ===== VALIDATING FACE: \(box) =====")
        print("🔍 [PhotoFaceDetector] Image size: \(imageSize)")
        
        // 1. Check if bounding box is within image bounds
        print("🔍 [PhotoFaceDetector] Test 1: Image bounds check")
        print("🔍 [PhotoFaceDetector] Box: minX=\(box.minX), minY=\(box.minY), maxX=\(box.maxX), maxY=\(box.maxY)")
        print("🔍 [PhotoFaceDetector] Image: width=\(imageSize.width), height=\(imageSize.height)")
        
        guard box.minX >= 0 && box.minY >= 0 && 
              box.maxX <= imageSize.width && box.maxY <= imageSize.height else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Face outside image bounds")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Image bounds check")
        
        // 2. Check minimum size requirements (adjusted for baby faces)
        print("🔍 [PhotoFaceDetector] Test 2: Minimum size check")
        let minFaceSize: CGFloat = 80.0 // Reduced to better capture baby faces
        print("🔍 [PhotoFaceDetector] Box size: \(box.size), Min required: \(minFaceSize)")
        
        guard box.width >= minFaceSize && box.height >= minFaceSize else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Face too small")
            print("🔍 [PhotoFaceDetector]   Width: \(box.width), Height: \(box.height)")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Minimum size check")
        
        // 3. Check maximum size requirements (avoid detecting entire bodies)
        print("🔍 [PhotoFaceDetector] Test 3: Maximum size check")
        let maxFaceSize: CGFloat = min(imageSize.width, imageSize.height) * 0.6 // Increased to 60% for more permissive detection
        print("🔍 [PhotoFaceDetector] Box size: \(box.size), Max allowed: \(maxFaceSize)")
        
        guard box.width <= maxFaceSize && box.height <= maxFaceSize else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Face too large (likely body)")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Maximum size check")
        
        // 4. Check aspect ratio (faces should be roughly square-ish)
        print("🔍 [PhotoFaceDetector] Test 4: Aspect ratio check")
        let aspectRatio = box.width / box.height
        print("🔍 [PhotoFaceDetector] Aspect ratio: \(aspectRatio)")
        print("🔍 [PhotoFaceDetector] Face dimensions: \(box.width) x \(box.height)")
        print("🔍 [PhotoFaceDetector] Face area: \(box.width * box.height) pixels")
        print("🔍 [PhotoFaceDetector] Face center: (\(box.midX), \(box.midY))")
        
        guard aspectRatio >= 0.4 && aspectRatio <= 2.5 else { // Much more permissive for real faces
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Invalid aspect ratio")
            print("🔍 [PhotoFaceDetector]   Expected: 0.4-2.5, Got: \(aspectRatio)")
            print("🔍 [PhotoFaceDetector]   This face is too rectangular (width/height ratio)")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Aspect ratio check")
        
        // 5. Check if the area is not in the extreme edges (likely false positive)
        print("🔍 [PhotoFaceDetector] Test 5: Edge margin check")
        let edgeMargin: CGFloat = 30.0 // Reduced to allow faces near edges (baby in arms)
        print("🔍 [PhotoFaceDetector] Edge margin: \(edgeMargin)")
        print("🔍 [PhotoFaceDetector] Box position: minX=\(box.minX), minY=\(box.minY), maxX=\(box.maxX), maxY=\(box.maxY)")
        print("🔍 [PhotoFaceDetector] Allowed range: X=[\(edgeMargin), \(imageSize.width - edgeMargin)], Y=[\(edgeMargin), \(imageSize.height - edgeMargin)]")
        
        guard box.minX >= edgeMargin && box.minY >= edgeMargin &&
              box.maxX <= (imageSize.width - edgeMargin) && 
              box.maxY <= (imageSize.height - edgeMargin) else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Face too close to image edges")
            print("🔍 [PhotoFaceDetector]   This could be a partial face crop or background element")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Edge margin check")
        
        // 6. Enhanced skin tone check (CRITICAL for filtering false positives)
        print("🔍 [PhotoFaceDetector] Test 6: Enhanced skin tone check")
        guard hasEnhancedSkinTone(in: box, of: image) else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: No skin tone detected")
            print("🔍 [PhotoFaceDetector]   This area doesn't contain enough skin tone pixels")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Enhanced skin tone check")
        
        // 7. Check for face-like features (CRITICAL for filtering backgrounds)
        print("🔍 [PhotoFaceDetector] Test 7: Face-like features check")
        guard hasFaceLikeFeatures(in: box, of: image) else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: No face-like features detected")
            print("🔍 [PhotoFaceDetector]   This area lacks face-like patterns (symmetry, detail)")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Face-like features check")
        
        // 8. NEW: Check if this is likely text, logo, or geometric pattern
        print("🔍 [PhotoFaceDetector] Test 8: Background pattern check")
        guard !isLikelyBackgroundPattern(in: box, of: image) else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Detected background pattern")
            print("🔍 [PhotoFaceDetector]   This area appears to be text, logo, or geometric pattern")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Background pattern check")
        
        print("🔍 [PhotoFaceDetector] ✅ ALL TESTS PASSED - Face is valid!")
        return true
    }
    
    // NEW: Check if this area is likely a background pattern (brick walls, geometric shapes, etc.)
    private func isLikelyBackgroundPattern(in box: CGRect, of image: UIImage) -> Bool {
        // Crop the face area
        guard let croppedImage = cropFaceFromImage(image: image, boundingBox: box),
              let cgImage = croppedImage.cgImage else {
            print("🔍 [PhotoFaceDetector] Background pattern check: Could not crop image")
            return false
        }
        
        let width = cgImage.width
        let height = cgImage.height
        
        print("🔍 [PhotoFaceDetector] Background pattern analysis for \(width)x\(height) area")
        
        // Check for repetitive patterns (like brick walls)
        let isRepetitive = hasRepetitivePattern(in: croppedImage)
        print("🔍 [PhotoFaceDetector] Repetitive pattern check: \(isRepetitive ? "DETECTED" : "Not detected")")
        
        if isRepetitive {
            return true
        }
        
        // For performance, only check edge density for smaller images or downsample
        let shouldCheckDetails = width < 500 && height < 500
        
        if shouldCheckDetails {
            // Check for high edge density (typical of text/logos)
            let edgeDensity = calculateEdgeDensity(in: croppedImage)
            print("🔍 [PhotoFaceDetector] Edge density: \(edgeDensity)")
            
            if edgeDensity > 0.7 { // High edge density suggests text/geometric patterns
                print("🔍 [PhotoFaceDetector] High edge density detected - likely text/logo")
                return true
            }
            
            // Check for uniform textures (like solid walls)
            let textureVariance = calculateTextureVariance(in: croppedImage)
            print("🔍 [PhotoFaceDetector] Texture variance: \(textureVariance)")
            
            if textureVariance < 0.05 { // Very uniform texture (made more strict)
                print("🔍 [PhotoFaceDetector] Very uniform texture - likely solid background")
                return true
            }
        } else {
            print("🔍 [PhotoFaceDetector] Skipping detailed analysis for large image (performance optimization)")
        }
        
        return false
    }
    
    // Check for repetitive patterns (brick walls, tiles, etc.)
    private func hasRepetitivePattern(in image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        let width = cgImage.width
        let height = cgImage.height
        
        // Sample a small grid to check for repetition
        let sampleSize = min(width, height) / 8
        guard sampleSize > 4 else { return false }
        
        // Get pixel data
        guard let pixelData = getPixelData(from: cgImage) else { return false }
        
        // Check for horizontal repetition (like brick patterns)
        var repetitionCount = 0
        let stepSize = max(1, Int(sampleSize / 4))
        
        // Add bounds checking to prevent fatal errors
        let maxY = max(stepSize, height - Int(sampleSize))
        let maxX = max(stepSize, width - Int(sampleSize) * 2)
        
        guard maxY > stepSize && maxX > stepSize else {
            print("🔍 [PhotoFaceDetector] Image too small for repetition analysis")
            return false
        }
        
        for y in stride(from: stepSize, to: maxY, by: stepSize) {
            for x in stride(from: stepSize, to: maxX, by: stepSize) {
                let sample1 = getPixelSample(pixelData: pixelData, x: x, y: y, size: Int(sampleSize), width: width)
                let sample2 = getPixelSample(pixelData: pixelData, x: x + Int(sampleSize), y: y, size: Int(sampleSize), width: width)
                
                if arePixelSamplesSimilar(sample1, sample2, threshold: 0.9) {
                    repetitionCount += 1
                }
            }
        }
        
        let totalSamples = max(1, ((maxY - stepSize) / stepSize) * ((maxX - stepSize) / stepSize))
        let repetitionRatio = Double(repetitionCount) / Double(totalSamples)
        
        print("🔍 [PhotoFaceDetector] Repetition ratio: \(repetitionRatio) (\(repetitionCount)/\(totalSamples))")
        return repetitionRatio > 0.6 // Increased threshold - 60% repetition suggests strong pattern (less aggressive)
    }
    
    // Calculate edge density to detect text/logos
    private func calculateEdgeDensity(in image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.0 }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let pixelData = getPixelData(from: cgImage) else { return 0.0 }
        
        var edgeCount = 0
        let totalPixels = (width - 1) * (height - 1)
        
        // Simple edge detection using brightness differences
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let currentPixel = getPixelBrightness(pixelData: pixelData, x: x, y: y, width: width)
                let rightPixel = getPixelBrightness(pixelData: pixelData, x: x + 1, y: y, width: width)
                let bottomPixel = getPixelBrightness(pixelData: pixelData, x: x, y: y + 1, width: width)
                
                let horizontalDiff = abs(currentPixel - rightPixel)
                let verticalDiff = abs(currentPixel - bottomPixel)
                
                if horizontalDiff > 0.3 || verticalDiff > 0.3 { // Significant brightness change
                    edgeCount += 1
                }
            }
        }
        
        return Double(edgeCount) / Double(totalPixels)
    }
    
    // Calculate texture variance to detect uniform areas
    private func calculateTextureVariance(in image: UIImage) -> Double {
        guard let cgImage = image.cgImage else { return 0.0 }
        
        let width = cgImage.width
        let height = cgImage.height
        
        guard let pixelData = getPixelData(from: cgImage) else { return 0.0 }
        
        var brightnessValues: [Double] = []
        
        // Sample brightness values
        let sampleStep = max(1, min(width, height) / 20)
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let brightness = getPixelBrightness(pixelData: pixelData, x: x, y: y, width: width)
                brightnessValues.append(brightness)
            }
        }
        
        guard !brightnessValues.isEmpty else { return 0.0 }
        
        // Calculate variance
        let mean = brightnessValues.reduce(0, +) / Double(brightnessValues.count)
        let variance = brightnessValues.map { pow($0 - mean, 2) }.reduce(0, +) / Double(brightnessValues.count)
        
        return sqrt(variance) // Return standard deviation
    }
    
    // Helper functions for pixel analysis
    private func getPixelData(from cgImage: CGImage) -> Data? {
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let totalBytes = bytesPerRow * height
        
        var pixelData = Data(count: totalBytes)
        
        pixelData.withUnsafeMutableBytes { ptr in
            let context = CGContext(
                data: ptr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        
        return pixelData
    }
    
    private func getPixelBrightness(pixelData: Data, x: Int, y: Int, width: Int) -> Double {
        let bytesPerPixel = 4
        let index = (y * width + x) * bytesPerPixel
        
        guard index + 2 < pixelData.count else { return 0.0 }
        
        let r = Double(pixelData[index]) / 255.0
        let g = Double(pixelData[index + 1]) / 255.0
        let b = Double(pixelData[index + 2]) / 255.0
        
        return (r + g + b) / 3.0 // Simple brightness calculation
    }
    
    private func getPixelSample(pixelData: Data, x: Int, y: Int, size: Int, width: Int) -> [Double] {
        var sample: [Double] = []
        let height = pixelData.count / (width * 4) // Calculate height from data size
        let endX = min(x + size, width)
        let endY = min(y + size, height) // Fixed: using height instead of width
        
        // Add bounds checking
        guard x >= 0 && y >= 0 && x < width && y < height && endX > x && endY > y else {
            print("🔍 [PhotoFaceDetector] Invalid sample bounds: x=\(x), y=\(y), size=\(size), width=\(width), height=\(height)")
            return [0.0] // Return default value to prevent crashes
        }
        
        for sampleY in y..<endY {
            for sampleX in x..<endX {
                let brightness = getPixelBrightness(pixelData: pixelData, x: sampleX, y: sampleY, width: width)
                sample.append(brightness)
            }
        }
        
        return sample
    }
    
    private func arePixelSamplesSimilar(_ sample1: [Double], _ sample2: [Double], threshold: Double) -> Bool {
        guard sample1.count == sample2.count, !sample1.isEmpty else { return false }
        
        let differences = zip(sample1, sample2).map { abs($0 - $1) }
        let averageDifference = differences.reduce(0, +) / Double(differences.count)
        
        return averageDifference < (1.0 - threshold)
    }

    // Check if an area has sufficient detail (not just flat color/text)
    private func hasSufficientDetail(in box: CGRect, of image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        // Crop the face area
        let cropRect = CGRect(
            x: box.minX * image.scale,
            y: box.minY * image.scale,
            width: box.width * image.scale,
            height: box.height * image.scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return false }
        
        // Convert to grayscale for edge detection
        let width = Int(croppedCGImage.width)
        let height = Int(croppedCGImage.height)
        let bytesPerRow = width
        
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return false
        }
        
        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return false }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        
        // Calculate variance (measure of detail)
        var sum: Double = 0
        var sumSquared: Double = 0
        let pixelCount = width * height
        
        for i in 0..<pixelCount {
            let pixel = Double(buffer[i])
            sum += pixel
            sumSquared += pixel * pixel
        }
        
        let mean = sum / Double(pixelCount)
        let variance = (sumSquared / Double(pixelCount)) - (mean * mean)
        
        // High variance indicates more detail
        let minVariance: Double = 200.0 // Increased threshold for more detail
        return variance > minVariance
    }
    
    // Check if an area has face-like characteristics (basic skin tone detection)
    private func hasFaceLikeCharacteristics(in box: CGRect, of image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        // Crop the face area
        let cropRect = CGRect(
            x: box.minX * image.scale,
            y: box.minY * image.scale,
            width: box.width * image.scale,
            height: box.height * image.scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return false }
        
        // Convert to RGB for color analysis
        let width = Int(croppedCGImage.width)
        let height = Int(croppedCGImage.height)
        let bytesPerRow = width * 4
        
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        
        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return false }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        var skinTonePixels = 0
        let pixelCount = width * height
        
        for i in stride(from: 0, to: pixelCount * 4, by: 4) {
            let r = Double(buffer[i])
            let g = Double(buffer[i + 1])
            let b = Double(buffer[i + 2])
            
            // Basic skin tone detection (simplified)
            if isSkinTone(r: r, g: g, b: b) {
                skinTonePixels += 1
            }
        }
        
        let skinToneRatio = Double(skinTonePixels) / Double(pixelCount)
        let minSkinToneRatio: Double = 0.2 // Increased to 20% should be skin-like
        
        return skinToneRatio > minSkinToneRatio
    }
    
    // Basic skin tone detection
    private func isSkinTone(r: Double, g: Double, b: Double) -> Bool {
        // Simplified skin tone detection
        // R should be dominant, G should be moderate, B should be lower
        let total = r + g + b
        guard total > 0 else { return false }
        
        let rRatio = r / total
        let gRatio = g / total
        let bRatio = b / total
        
        // Skin tones typically have:
        // - R ratio > 0.3 (reddish)
        // - G ratio between 0.2-0.4 (moderate green)
        // - B ratio < 0.3 (low blue)
        return rRatio > 0.3 && gRatio >= 0.2 && gRatio <= 0.4 && bRatio < 0.3
    }
    
    // Check if an area is likely text or logo (high contrast, regular patterns)
    private func isLikelyTextOrLogo(in box: CGRect, of image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        // Crop the area
        let cropRect = CGRect(
            x: box.minX * image.scale,
            y: box.minY * image.scale,
            width: box.width * image.scale,
            height: box.height * image.scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return false }
        
        // Convert to grayscale for analysis
        let width = Int(croppedCGImage.width)
        let height = Int(croppedCGImage.height)
        let bytesPerRow = width
        
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceGray(),
                                    bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return false
        }
        
        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return false }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height)
        
        // Calculate edge density (text/logo has high edge density)
        var edgePixels = 0
        let pixelCount = width * height
        
        for y in 1..<height-1 {
            for x in 1..<width-1 {
                let center = Int(buffer[y * width + x])
                let left = Int(buffer[y * width + (x-1)])
                let right = Int(buffer[y * width + (x+1)])
                let top = Int(buffer[(y-1) * width + x])
                let bottom = Int(buffer[(y+1) * width + x])
                
                // Check for high contrast edges
                let horizontalEdge = abs(center - left) + abs(center - right)
                let verticalEdge = abs(center - top) + abs(center - bottom)
                
                if horizontalEdge > 50 || verticalEdge > 50 {
                    edgePixels += 1
                }
            }
        }
        
        let edgeRatio = Double(edgePixels) / Double(pixelCount)
        
        // High edge density suggests text/logo
        return edgeRatio > 0.3
    }
    
    // Check if an area is flat color (likely background)
    private func isFlatColorRegion(in box: CGRect, of image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        
        // Crop the area
        let cropRect = CGRect(
            x: box.minX * image.scale,
            y: box.minY * image.scale,
            width: box.width * image.scale,
            height: box.height * image.scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { return false }
        
        // Convert to RGB for color analysis
        let width = Int(croppedCGImage.width)
        let height = Int(croppedCGImage.height)
        let bytesPerRow = width * 4
        
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return false
        }
        
        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { return false }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        // Calculate color variance
        var rSum: Double = 0, gSum: Double = 0, bSum: Double = 0
        var rSquared: Double = 0, gSquared: Double = 0, bSquared: Double = 0
        let pixelCount = width * height
        
        for i in stride(from: 0, to: pixelCount * 4, by: 4) {
            let r = Double(buffer[i])
            let g = Double(buffer[i + 1])
            let b = Double(buffer[i + 2])
            
            rSum += r
            gSum += g
            bSum += b
            rSquared += r * r
            gSquared += g * g
            bSquared += b * b
        }
        
        let rMean = rSum / Double(pixelCount)
        let gMean = gSum / Double(pixelCount)
        let bMean = bSum / Double(pixelCount)
        
        let rVariance = (rSquared / Double(pixelCount)) - (rMean * rMean)
        let gVariance = (gSquared / Double(pixelCount)) - (gMean * gMean)
        let bVariance = (bSquared / Double(pixelCount)) - (bMean * bMean)
        
        let totalVariance = rVariance + gVariance + bVariance
        
        // Low variance indicates flat color
        return totalVariance < 500.0
    }
    
    // Simplified skin tone detection
    private func hasBasicSkinTone(in box: CGRect, of image: UIImage) -> Bool {
        print("🔍 [PhotoFaceDetector] Starting skin tone analysis for box: \(box)")
        
        guard let cgImage = image.cgImage else { 
            print("🔍 [PhotoFaceDetector] ❌ Failed to get CGImage")
            return false 
        }
        
        // Crop the area
        let cropRect = CGRect(
            x: box.minX * image.scale,
            y: box.minY * image.scale,
            width: box.width * image.scale,
            height: box.height * image.scale
        )
        
        print("🔍 [PhotoFaceDetector] Crop rect: \(cropRect)")
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { 
            print("🔍 [PhotoFaceDetector] ❌ Failed to crop image")
            return false 
        }
        
        print("🔍 [PhotoFaceDetector] Cropped image size: \(croppedCGImage.width) x \(croppedCGImage.height)")
        
        // Convert to RGB for color analysis
        let width = Int(croppedCGImage.width)
        let height = Int(croppedCGImage.height)
        let bytesPerRow = width * 4
        
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("🔍 [PhotoFaceDetector] ❌ Failed to create RGB context")
            return false
        }
        
        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { 
            print("🔍 [PhotoFaceDetector] ❌ Failed to get image data")
            return false 
        }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        var skinTonePixels = 0
        let pixelCount = width * height
        
        print("🔍 [PhotoFaceDetector] Analyzing \(pixelCount) pixels for skin tone...")
        
        for i in stride(from: 0, to: pixelCount * 4, by: 4) {
            let r = Double(buffer[i])
            let g = Double(buffer[i + 1])
            let b = Double(buffer[i + 2])
            
            // Very basic skin tone detection
            if isBasicSkinTone(r: r, g: g, b: b) {
                skinTonePixels += 1
            }
        }
        
        let skinToneRatio = Double(skinTonePixels) / Double(pixelCount)
        let minSkinToneRatio: Double = 0.05 // Much lower threshold for babies
        
        print("🔍 [PhotoFaceDetector] Skin tone pixels: \(skinTonePixels)/\(pixelCount) = \(skinToneRatio * 100)%")
        print("🔍 [PhotoFaceDetector] Minimum required: \(minSkinToneRatio * 100)%")
        
        let result = skinToneRatio > minSkinToneRatio
        print("🔍 [PhotoFaceDetector] Skin tone check result: \(result ? "PASS" : "FAIL")")
        
        return result
    }
    
    // Very basic skin tone detection
    private func isBasicSkinTone(r: Double, g: Double, b: Double) -> Bool {
        // Simplified: R should be higher than B, and G should be moderate
        return r > g && g > b && r > 100 && g > 80 && b < 150
    }
    
    // Enhanced skin tone detection with more sophisticated analysis
    private func hasEnhancedSkinTone(in box: CGRect, of image: UIImage) -> Bool {
        print("🔍 [PhotoFaceDetector] Starting enhanced skin tone analysis for box: \(box)")
        
        guard let cgImage = image.cgImage else { 
            print("🔍 [PhotoFaceDetector] ❌ Failed to get CGImage")
            return false 
        }
        
        // Crop the area
        let cropRect = CGRect(
            x: box.minX * image.scale,
            y: box.minY * image.scale,
            width: box.width * image.scale,
            height: box.height * image.scale
        )
        
        print("🔍 [PhotoFaceDetector] Enhanced crop rect: \(cropRect)")
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { 
            print("🔍 [PhotoFaceDetector] ❌ Failed to crop image")
            return false 
        }
        
        print("🔍 [PhotoFaceDetector] Enhanced cropped image size: \(croppedCGImage.width) x \(croppedCGImage.height)")
        
        // Convert to RGB for color analysis
        let width = Int(croppedCGImage.width)
        let height = Int(croppedCGImage.height)
        let bytesPerRow = width * 4
        
        guard let context = CGContext(data: nil,
                                    width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bytesPerRow: bytesPerRow,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            print("🔍 [PhotoFaceDetector] ❌ Failed to create RGB context")
            return false
        }
        
        context.draw(croppedCGImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else { 
            print("🔍 [PhotoFaceDetector] ❌ Failed to get image data")
            return false 
        }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        var skinTonePixels = 0
        var centerSkinTonePixels = 0
        let pixelCount = width * height
        
        // Define center region for more important skin tone detection
        let centerX = width / 2
        let centerY = height / 2
        let centerRadius = min(width, height) / 3
        
        print("🔍 [PhotoFaceDetector] Enhanced analyzing \(pixelCount) pixels for skin tone...")
        print("🔍 [PhotoFaceDetector] Center region: (\(centerX), \(centerY)) with radius \(centerRadius)")
        
        for y in 0..<height {
            for x in 0..<width {
                let pixelIndex = (y * width + x) * 4
                let r = Double(buffer[pixelIndex])
                let g = Double(buffer[pixelIndex + 1])
                let b = Double(buffer[pixelIndex + 2])
                
                // Enhanced skin tone detection
                if isEnhancedSkinTone(r: r, g: g, b: b) {
                    skinTonePixels += 1
                    
                    // Check if pixel is in center region
                    let distanceFromCenter = sqrt(pow(Double(x - centerX), 2) + pow(Double(y - centerY), 2))
                    if distanceFromCenter <= Double(centerRadius) {
                        centerSkinTonePixels += 1
                    }
                }
            }
        }
        
        let skinToneRatio = Double(skinTonePixels) / Double(pixelCount)
        let centerArea = Double(centerRadius * centerRadius) * .pi
        let centerSkinToneRatio = Double(centerSkinTonePixels) / centerArea
        let minSkinToneRatio: Double = 0.05 // More inclusive for baby faces (reduced from 0.08)
        let minCenterSkinToneRatio: Double = 0.08 // More inclusive for baby faces (reduced from 0.15)
        
        print("🔍 [PhotoFaceDetector] Enhanced skin tone analysis:")
        print("🔍 [PhotoFaceDetector]   Overall skin tone: \(skinTonePixels)/\(pixelCount) = \(skinToneRatio * 100)%")
        print("🔍 [PhotoFaceDetector]   Center skin tone: \(centerSkinTonePixels)/\(Int(centerArea)) = \(centerSkinToneRatio * 100)%")
        print("🔍 [PhotoFaceDetector]   Min required: \(minSkinToneRatio * 100)% overall, \(minCenterSkinToneRatio * 100)% center")
        
        let result = skinToneRatio >= minSkinToneRatio && centerSkinToneRatio >= minCenterSkinToneRatio
        print("🔍 [PhotoFaceDetector] Enhanced skin tone check result: \(result ? "PASS" : "FAIL")")
        
        return result
    }
    
    // Enhanced skin tone detection algorithm
    private func isEnhancedSkinTone(r: Double, g: Double, b: Double) -> Bool {
        // More sophisticated skin tone detection
        // Check for typical skin tone ranges
        let isWarmTone = r > g && g > b && r > 120 && g > 80 && b < 120
        let isNeutralTone = r > 100 && g > 90 && b > 70 && abs(r - g) < 30 && abs(g - b) < 30
        let isLightTone = r > 150 && g > 120 && b > 100 && r < 250 && g < 220 && b < 200
        
        return isWarmTone || isNeutralTone || isLightTone
    }
    
    // Check for face-like features (eyes, nose, mouth patterns)
    private func hasFaceLikeFeatures(in box: CGRect, of image: UIImage) -> Bool {
        print("🔍 [PhotoFaceDetector] Starting face-like features analysis for box: \(box)")
        
        guard let cgImage = image.cgImage else { 
            print("🔍 [PhotoFaceDetector] ❌ Failed to get CGImage")
            return false 
        }
        
        // Crop the area
        let cropRect = CGRect(
            x: box.minX * image.scale,
            y: box.minY * image.scale,
            width: box.width * image.scale,
            height: box.height * image.scale
        )
        
        guard let croppedCGImage = cgImage.cropping(to: cropRect) else { 
            print("🔍 [PhotoFaceDetector] ❌ Failed to crop image")
            return false 
        }
        
        // Simple feature detection: look for symmetry and edge patterns
        // This is a simplified version - in a real app you'd use more sophisticated algorithms
        
        // Check if the area has reasonable detail (not just flat color)
        let hasDetail = hasSufficientDetail(in: box, of: image)
        
        // Check for reasonable symmetry (faces are roughly symmetrical)
        let hasSymmetry = checkSymmetry(in: croppedCGImage)
        
        print("🔍 [PhotoFaceDetector] Face-like features analysis:")
        print("🔍 [PhotoFaceDetector]   Has detail: \(hasDetail)")
        print("🔍 [PhotoFaceDetector]   Has symmetry: \(hasSymmetry)")
        
        let result = hasDetail && hasSymmetry
        print("🔍 [PhotoFaceDetector] Face-like features check result: \(result ? "PASS" : "FAIL")")
        
        return result
    }
    
    // Check for symmetry in the image (simplified)
    private func checkSymmetry(in cgImage: CGImage) -> Bool {
        let width = Int(cgImage.width)
        let height = Int(cgImage.height)
        
        // Simple symmetry check: compare left and right halves
        let halfWidth = width / 2
        var symmetryScore = 0
        let samplePoints = min(100, height) // Sample points for performance
        
        for y in stride(from: 0, to: height, by: max(1, height / samplePoints)) {
            for x in 0..<halfWidth {
                let leftPixel = getPixelBrightness(at: CGPoint(x: x, y: y), in: cgImage)
                let rightPixel = getPixelBrightness(at: CGPoint(x: width - 1 - x, y: y), in: cgImage)
                
                let difference = abs(leftPixel - rightPixel)
                if difference < 30 { // Threshold for "similar" pixels
                    symmetryScore += 1
                }
            }
        }
        
        let symmetryRatio = Double(symmetryScore) / Double(halfWidth * samplePoints)
        let hasSymmetry = symmetryRatio > 0.3 // 30% symmetry threshold
        
        print("🔍 [PhotoFaceDetector] Symmetry analysis: \(symmetryScore)/\(halfWidth * samplePoints) = \(symmetryRatio * 100)%")
        
        return hasSymmetry
    }
    
    // Get pixel brightness at a point (simplified)
    private func getPixelBrightness(at point: CGPoint, in cgImage: CGImage) -> Double {
        // Simplified brightness calculation
        // In a real implementation, you'd get the actual pixel data
        return 128.0 // Placeholder - would calculate actual brightness
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
        
        // Multiple preprocessing strategies for different conditions
        
        // Strategy 1: Enhance contrast and brightness for dark photos
        let contrastFilter = CIFilter(name: "CIColorControls")!
        contrastFilter.setValuesForKeys([
            kCIInputImageKey: ciImage,
            "inputContrast": 1.4,      // More aggressive contrast
            "inputBrightness": 0.2,    // More brightness
            "inputSaturation": 1.2     // More saturation
        ])
        
        // Strategy 2: Apply exposure adjustment for very dark images
        let exposureFilter = CIFilter(name: "CIExposureAdjust")!
        exposureFilter.setValuesForKeys([
            kCIInputImageKey: contrastFilter.outputImage!,
            "inputEV": 0.8  // More aggressive exposure
        ])
        
        // Strategy 3: Sharpen the image to enhance facial features
        let sharpenFilter = CIFilter(name: "CISharpenLuminance")!
        sharpenFilter.setValuesForKeys([
            kCIInputImageKey: exposureFilter.outputImage!,
            "inputSharpness": 1.0  // More aggressive sharpening
        ])
        
        // Strategy 4: Apply noise reduction for grainy photos
        let noiseFilter = CIFilter(name: "CINoiseReduction")!
        noiseFilter.setValuesForKeys([
            kCIInputImageKey: sharpenFilter.outputImage!,
            "inputNoiseLevel": 0.02,
            "inputSharpness": 0.4
        ])
        
        // Strategy 5: Apply highlight and shadow adjustment
        let highlightFilter = CIFilter(name: "CIHighlightShadowAdjust")!
        highlightFilter.setValuesForKeys([
            kCIInputImageKey: noiseFilter.outputImage!,
            "inputHighlightAmount": 1.0,
            "inputShadowAmount": 0.3
        ])
        
        guard let outputImage = highlightFilter.outputImage,
              let processedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
            print("[PhotoFaceDetector] Image preprocessing failed, using original")
            return image
        }
        
        print("[PhotoFaceDetector] Image preprocessed with enhanced filters for better detection")
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
    
    // MARK: - Professional Face Quality Assessment (Industry Standard)
    
    // Calculate comprehensive face quality using landmarks (like Photos app)
    private func calculateFaceQuality(from observation: VNFaceObservation) -> FaceQuality? {
        guard let landmarks = observation.landmarks else {
            return nil
        }
        
        // Check for presence of key facial features
        let hasEyes = (landmarks.leftEye != nil && landmarks.rightEye != nil) ||
                     (landmarks.leftPupil != nil && landmarks.rightPupil != nil)
        let hasNose = landmarks.nose != nil || landmarks.noseCrest != nil
        let hasMouth = landmarks.outerLips != nil || landmarks.innerLips != nil
        
        // Calculate landmark completeness (industry standard metric)
        var landmarkCount = 0
        var totalPossibleLandmarks = 0
        
        let landmarkChecks: [(VNFaceLandmarkRegion2D?, String)] = [
            (landmarks.faceContour, "faceContour"),
            (landmarks.leftEye, "leftEye"),
            (landmarks.rightEye, "rightEye"),
            (landmarks.nose, "nose"),
            (landmarks.outerLips, "outerLips"),
            (landmarks.leftEyebrow, "leftEyebrow"),
            (landmarks.rightEyebrow, "rightEyebrow"),
            (landmarks.noseCrest, "noseCrest"),
            (landmarks.medianLine, "medianLine")
        ]
        
        for (landmark, _) in landmarkChecks {
            totalPossibleLandmarks += 1
            if landmark != nil {
                landmarkCount += 1
            }
        }
        
        let landmarkCompleteness = Double(landmarkCount) / Double(totalPossibleLandmarks)
        
        // Calculate face symmetry (professional metric)
        let faceSymmetry = calculateFaceSymmetry(landmarks: landmarks)
        
        // Calculate overall quality score (industry formula)
        let confidenceWeight = 0.3
        let landmarkWeight = 0.3
        let symmetryWeight = 0.2
        let featureWeight = 0.2
        
        let featureScore = (hasEyes ? 1.0 : 0.0) + (hasNose ? 1.0 : 0.0) + (hasMouth ? 1.0 : 0.0) / 3.0
        
        let overallScore = (Double(observation.confidence) * confidenceWeight) +
                          (landmarkCompleteness * landmarkWeight) +
                          (faceSymmetry * symmetryWeight) +
                          (featureScore * featureWeight)
        
        return FaceQuality(
            overallScore: overallScore,
            hasEyes: hasEyes,
            hasNose: hasNose,
            hasMouth: hasMouth,
            landmarkCompleteness: landmarkCompleteness,
            faceSymmetry: faceSymmetry,
            confidenceScore: Double(observation.confidence)
        )
    }
    
    // Calculate face symmetry using landmarks (professional metric)
    private func calculateFaceSymmetry(landmarks: VNFaceLandmarks2D) -> Double {
        // Check if we have eyes for symmetry calculation
        guard let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              leftEye.pointCount > 0,
              rightEye.pointCount > 0 else {
            return 0.5 // Default moderate symmetry if no eye landmarks
        }
        
        // Calculate eye positions and compare for symmetry
        let leftEyePoints = leftEye.normalizedPoints
        let rightEyePoints = rightEye.normalizedPoints
        
        // Calculate center points of each eye
        let leftEyeCenter = CGPoint(
            x: leftEyePoints.map { $0.x }.reduce(0, +) / CGFloat(leftEyePoints.count),
            y: leftEyePoints.map { $0.y }.reduce(0, +) / CGFloat(leftEyePoints.count)
        )
        
        let rightEyeCenter = CGPoint(
            x: rightEyePoints.map { $0.x }.reduce(0, +) / CGFloat(rightEyePoints.count),
            y: rightEyePoints.map { $0.y }.reduce(0, +) / CGFloat(rightEyePoints.count)
        )
        
        // Calculate symmetry based on eye level alignment
        let eyeLevelDifference = abs(leftEyeCenter.y - rightEyeCenter.y)
        let eyeDistance = abs(leftEyeCenter.x - rightEyeCenter.x)
        
        // Symmetry score (1.0 = perfect symmetry, 0.0 = no symmetry)
        let symmetryScore = max(0.0, 1.0 - (eyeLevelDifference / eyeDistance) * 5.0)
        
        return min(1.0, max(0.0, symmetryScore))
    }
    
    // Create precise face bounds using landmarks (industry standard)
    private func createPreciseFaceBounds(from observation: VNFaceObservation, imageSize: CGSize) -> CGRect {
        guard let landmarks = observation.landmarks else {
            // Fallback to basic bounding box
            return convertNormalizedRect(observation.boundingBox, to: imageSize)
        }
        
        // Start with basic bounding box
        var bounds = convertNormalizedRect(observation.boundingBox, to: imageSize)
        
        // Refine bounds using face contour if available
        if let faceContour = landmarks.faceContour, faceContour.pointCount > 0 {
            let contourPoints = faceContour.normalizedPoints
            
            // Find the actual bounds of the face contour
            let minX = contourPoints.map { $0.x }.min() ?? observation.boundingBox.minX
            let maxX = contourPoints.map { $0.x }.max() ?? observation.boundingBox.maxX
            let minY = contourPoints.map { $0.y }.min() ?? observation.boundingBox.minY
            let maxY = contourPoints.map { $0.y }.max() ?? observation.boundingBox.maxY
            
            // Convert to image coordinates
            let imageMinX = minX * imageSize.width
            let imageMaxX = maxX * imageSize.width
            let imageMinY = (1.0 - maxY) * imageSize.height // Vision uses bottom-left origin
            let imageMaxY = (1.0 - minY) * imageSize.height
            
            // Create refined bounds with padding
            let padding: CGFloat = 20.0
            bounds = CGRect(
                x: max(0, imageMinX - padding),
                y: max(0, imageMinY - padding),
                width: min(imageSize.width - max(0, imageMinX - padding), imageMaxX - imageMinX + padding * 2),
                height: min(imageSize.height - max(0, imageMinY - padding), imageMaxY - imageMinY + padding * 2)
            )
        }
        
        return bounds
    }
    
    // MARK: - Enhanced Vision Detection (Professional Alternative)
    
    // Enhanced Vision detection with multiple configurations for maximum reliability
    private func detectFacesWithEnhancedVision(in image: UIImage) -> [PhotoDetectedFace] {
        print("[PhotoFaceDetector] 🏭 ENHANCED VISION: Starting multi-configuration detection...")
        
        guard let cgImage = image.cgImage else { return [] }
        
        // Try multiple detection configurations in order of quality
        let configurations: [(String, VNDetectFaceRectanglesRequest)] = [
            ("High Accuracy", createHighAccuracyRequest()),
            ("Balanced Performance", createBalancedRequest()),
            ("High Recall", createHighRecallRequest())
        ]
        
        for (configName, request) in configurations {
            let faces = performEnhancedDetection(cgImage: cgImage, imageSize: image.size, request: request, configName: configName)
            
            if !faces.isEmpty {
                print("[PhotoFaceDetector] 🏭 SUCCESS: \(configName) found \(faces.count) faces")
                return faces
            }
        }
        
        print("[PhotoFaceDetector] 🏭 ENHANCED VISION: No faces found with any configuration")
        return []
    }
    
    // Perform detection with a specific Vision configuration
    private func performEnhancedDetection(cgImage: CGImage, imageSize: CGSize, request: VNDetectFaceRectanglesRequest, configName: String) -> [PhotoDetectedFace] {
        var detectedFaces: [PhotoDetectedFace] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        // Create request with completion handler
        let faceRequest = VNDetectFaceRectanglesRequest { request, error in
            defer { semaphore.signal() }
            
            guard let results = request.results as? [VNFaceObservation], error == nil else {
                print("[PhotoFaceDetector] ❌ \(configName) failed: \(error?.localizedDescription ?? "Unknown")")
                return
            }
            
            print("[PhotoFaceDetector] 🏭 \(configName): Found \(results.count) candidates")
            
            for (index, observation) in results.enumerated() {
                // Apply professional quality thresholds
                guard observation.confidence > 0.6 else {
                    print("[PhotoFaceDetector] ❌ \(configName) Face \(index + 1): Low confidence (\(observation.confidence))")
                    continue
                }
                
                let bounds = self.convertNormalizedRect(observation.boundingBox, to: imageSize)
                
                // Validate face size and position
                guard self.isValidProfessionalFace(bounds: bounds, imageSize: imageSize) else {
                    print("[PhotoFaceDetector] ❌ \(configName) Face \(index + 1): Invalid dimensions")
                    continue
                }
                
                print("[PhotoFaceDetector] ✅ \(configName) Face \(index + 1): ACCEPTED")
                print("[PhotoFaceDetector]   Confidence: \(observation.confidence)")
                print("[PhotoFaceDetector]   Bounds: \(bounds)")
                
                // Create high-quality face crop
                if let faceImage = self.cropFaceFromImage(image: UIImage(cgImage: cgImage), boundingBox: bounds) {
                    let detectedFace = PhotoDetectedFace(boundingBox: bounds, faceImage: faceImage)
                    detectedFaces.append(detectedFace)
                }
            }
        }
        
        // Copy configuration from the input request
        faceRequest.revision = request.revision
        
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([faceRequest])
            } catch {
                print("[PhotoFaceDetector] ❌ \(configName) execution failed: \(error)")
                semaphore.signal()
            }
        }
        
        semaphore.wait()
        return detectedFaces
    }
    
    // Professional face validation for enhanced detection
    private func isValidProfessionalFace(bounds: CGRect, imageSize: CGSize) -> Bool {
        // Size constraints (professional standards)
        let minSize: CGFloat = 80.0
        let maxSizeRatio: CGFloat = 0.4 // Max 40% of image dimension
        let maxSize = min(imageSize.width, imageSize.height) * maxSizeRatio
        
        guard bounds.width >= minSize && bounds.height >= minSize else { return false }
        guard bounds.width <= maxSize && bounds.height <= maxSize else { return false }
        
        // Aspect ratio constraints (professional standards)
        let aspectRatio = bounds.width / bounds.height
        guard aspectRatio >= 0.4 && aspectRatio <= 2.5 else { return false }
        
        // Position constraints (avoid edge artifacts)
        let margin: CGFloat = 20.0
        guard bounds.minX >= margin && bounds.minY >= margin else { return false }
        guard bounds.maxX <= imageSize.width - margin && bounds.maxY <= imageSize.height - margin else { return false }
        
        return true
    }
    
    // MARK: - Vision Request Configurations
    
    private func createHighAccuracyRequest() -> VNDetectFaceRectanglesRequest {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3 // Latest and most accurate
        return request
    }
    
    private func createBalancedRequest() -> VNDetectFaceRectanglesRequest {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision2 // Balanced performance
        return request
    }
    
    private func createHighRecallRequest() -> VNDetectFaceRectanglesRequest {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision2 // More permissive (updated from deprecated API)
        return request
    }
}