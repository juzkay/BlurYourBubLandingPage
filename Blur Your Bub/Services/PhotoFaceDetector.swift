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
    
    // Enhanced face detection with landmarks for more precise boundaries
    func detectFacesWithLandmarks(in image: UIImage) -> [PhotoDetectedFace] {
        guard let cgImage = image.cgImage else { return [] }
        let ciImage = CIImage(cgImage: cgImage)
        
        var detectedFaces: [PhotoDetectedFace] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        // Use face landmarks for more precise detection
        let faceLandmarksRequest = VNDetectFaceLandmarksRequest { request, error in
            defer { semaphore.signal() }
            
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
                if faceObservation.confidence > 0.2 { // Even lower for landmarks
                    let faceImage = self.cropFaceFromImage(image: image, boundingBox: boundingBox)
                    let detectedFace = PhotoDetectedFace(boundingBox: boundingBox, faceImage: faceImage)
                    detectedFaces.append(detectedFace)
                    print("[PhotoFaceDetector] Added landmarks face with confidence \(faceObservation.confidence): \(boundingBox)")
                } else {
                    print("[PhotoFaceDetector] Rejected landmarks face with low confidence \(faceObservation.confidence): \(boundingBox)")
                }
            }
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
        
        // 2. Check minimum size requirements (very strict)
        print("🔍 [PhotoFaceDetector] Test 2: Minimum size check")
        let minFaceSize: CGFloat = 100.0
        print("🔍 [PhotoFaceDetector] Box size: \(box.size), Min required: \(minFaceSize)")
        
        guard box.width >= minFaceSize && box.height >= minFaceSize else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Face too small")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Minimum size check")
        
        // 3. Check maximum size requirements (avoid detecting entire bodies)
        print("🔍 [PhotoFaceDetector] Test 3: Maximum size check")
        let maxFaceSize: CGFloat = min(imageSize.width, imageSize.height) * 0.5 // Increased from 0.3
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
        
        guard aspectRatio >= 0.5 && aspectRatio <= 2.0 else { // Much more permissive
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Invalid aspect ratio")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Aspect ratio check")
        
        // 5. Check if the area is not in the extreme edges (likely false positive)
        print("🔍 [PhotoFaceDetector] Test 5: Edge margin check")
        let edgeMargin: CGFloat = 50.0
        print("🔍 [PhotoFaceDetector] Edge margin: \(edgeMargin)")
        print("🔍 [PhotoFaceDetector] Box position: minX=\(box.minX), minY=\(box.minY), maxX=\(box.maxX), maxY=\(box.maxY)")
        print("🔍 [PhotoFaceDetector] Allowed range: X=[\(edgeMargin), \(imageSize.width - edgeMargin)], Y=[\(edgeMargin), \(imageSize.height - edgeMargin)]")
        
        guard box.minX >= edgeMargin && box.minY >= edgeMargin &&
              box.maxX <= (imageSize.width - edgeMargin) && 
              box.maxY <= (imageSize.height - edgeMargin) else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: Face too close to image edges")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Edge margin check")
        
        // 6. Simple skin tone check (much simpler than before)
        print("🔍 [PhotoFaceDetector] Test 6: Skin tone check")
        guard hasBasicSkinTone(in: box, of: image) else {
            print("🔍 [PhotoFaceDetector] ❌ FAILED: No skin tone detected")
            return false
        }
        print("🔍 [PhotoFaceDetector] ✅ PASSED: Skin tone check")
        
        print("🔍 [PhotoFaceDetector] ✅ ALL TESTS PASSED - Face is valid!")
        return true
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
}