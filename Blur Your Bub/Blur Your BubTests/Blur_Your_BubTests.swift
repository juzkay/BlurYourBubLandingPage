import XCTest
@testable import Blur_Your_Bub

class BlurProcessorTests: XCTestCase {
    func testApplyBlurWithSimplePath() {
        // Create a solid color image
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        // Draw a path in the center
        let path = BlurPath(points: [CGPoint(x: 40, y: 40), CGPoint(x: 60, y: 60)])
        // Apply blur
        let blurred = BlurProcessor.applyBlur(to: image, with: [path], blurRadius: 20)
        // Assert output is not nil and not identical to input
        XCTAssertNotNil(blurred)
        XCTAssertNotEqual(image.pngData(), blurred.pngData(), "Blurred image should differ from original")
    }
} 