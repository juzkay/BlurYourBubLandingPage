import CoreGraphics
import UIKit

struct PhotoDetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let faceImage: UIImage? // Cropped face image for UI preview
    var isSelected: Bool = false // Whether this face will be blurred
    
    init(boundingBox: CGRect, faceImage: UIImage? = nil) {
        self.boundingBox = boundingBox
        self.faceImage = faceImage
    }
}