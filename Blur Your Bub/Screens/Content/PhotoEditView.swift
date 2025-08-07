import SwiftUI
import UIKit

// MARK: - CGPoint Extension
extension CGPoint {
    func distance(to point: CGPoint) -> CGFloat {
        let dx = x - point.x
        let dy = y - point.y
        return sqrt(dx * dx + dy * dy)
    }
}

// MARK: - PhotoEditView (SwiftUI wrapper)
struct PhotoEditView: UIViewRepresentable {
    let image: UIImage
    let isDrawingMode: Bool
    let blurPaths: [BlurPath]
    let emojiStickers: [EmojiSticker]
    let onPathAdded: (BlurPath) -> Void
    let onEmojiAdded: (EmojiSticker) -> Void
    
    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        
        // UIScrollView setup with zoom functionality
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 5.0
        scrollView.zoomScale = 1.0
        
        // UIImageView setup
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.image = image
        imageView.isUserInteractionEnabled = true
        
        // Add image view to scroll view
        scrollView.addSubview(imageView)
        containerView.addSubview(scrollView)
        
        // Store references
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.containerView = containerView
        context.coordinator.originalImage = image
        
        // Setup constraints
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
        
        // Setup drawing overlay
        let drawingOverlay = DrawingOverlayView(
            blurPaths: blurPaths,
            emojiStickers: emojiStickers,
            isDrawingMode: isDrawingMode,
            onPathAdded: onPathAdded,
            onEmojiAdded: onEmojiAdded,
            scrollView: scrollView,
            imageView: imageView,
            originalImage: image
        )
        drawingOverlay.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(drawingOverlay)
        
        NSLayoutConstraint.activate([
            drawingOverlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            drawingOverlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            drawingOverlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            drawingOverlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        context.coordinator.drawingOverlay = drawingOverlay
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update image
        context.coordinator.imageView?.image = image
        
        // Update drawing overlay
        context.coordinator.drawingOverlay?.updatePaths(blurPaths)
        context.coordinator.drawingOverlay?.updateEmojiStickers(emojiStickers)
        context.coordinator.drawingOverlay?.updateDrawingMode(isDrawingMode)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        var scrollView: UIScrollView?
        var imageView: UIImageView?
        var containerView: UIView?
        var drawingOverlay: DrawingOverlayView?
        var originalImage: UIImage?
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
    }
}

// Drawing overlay view with simplified coordinate transformations
class DrawingOverlayView: UIView {
    private var blurPaths: [BlurPath] = []
    private var emojiStickers: [EmojiSticker] = []
    private var isDrawingMode: Bool = false
    private var onPathAdded: (BlurPath) -> Void
    private var onEmojiAdded: (EmojiSticker) -> Void
    
    private var currentPath: [CGPoint] = []
    private var isDrawing = false
    
    // References for coordinate transformations
    weak var scrollView: UIScrollView?
    weak var imageView: UIImageView?
    weak var originalImage: UIImage?
    
    init(blurPaths: [BlurPath], emojiStickers: [EmojiSticker], isDrawingMode: Bool, onPathAdded: @escaping (BlurPath) -> Void, onEmojiAdded: @escaping (EmojiSticker) -> Void, scrollView: UIScrollView, imageView: UIImageView, originalImage: UIImage) {
        self.blurPaths = blurPaths
        self.emojiStickers = emojiStickers
        self.isDrawingMode = isDrawingMode
        self.onPathAdded = onPathAdded
        self.onEmojiAdded = onEmojiAdded
        self.scrollView = scrollView
        self.imageView = imageView
        self.originalImage = originalImage
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updatePaths(_ paths: [BlurPath]) {
        blurPaths = paths
        setNeedsDisplay()
    }
    
    func updateEmojiStickers(_ stickers: [EmojiSticker]) {
        emojiStickers = stickers
        setNeedsDisplay()
    }
    
    func updateDrawingMode(_ mode: Bool) {
        isDrawingMode = mode
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingMode, let touch = touches.first else { 
            // If not in drawing mode, pass touches to scroll view for zoom
            super.touchesBegan(touches, with: event)
            return 
        }
        isDrawing = true
        let touchPoint = touch.location(in: self)
        let imagePoint = convertTouchToImageCoordinates(touch: touchPoint)
        currentPath = [imagePoint]
        setNeedsDisplay()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingMode, isDrawing, let touch = touches.first else { 
            // If not in drawing mode, pass touches to scroll view for zoom
            super.touchesMoved(touches, with: event)
            return 
        }
        let touchPoint = touch.location(in: self)
        let imagePoint = convertTouchToImageCoordinates(touch: touchPoint)
        currentPath.append(imagePoint)
        setNeedsDisplay()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingMode, isDrawing else { 
            // If not in drawing mode, pass touches to scroll view for zoom
            super.touchesEnded(touches, with: event)
            return 
        }
        isDrawing = false
        
        if currentPath.count > 1 {
            let blurPath = BlurPath(points: currentPath)
            onPathAdded(blurPath)
        }
        
        currentPath = []
        setNeedsDisplay()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingMode, isDrawing else { 
            // If not in drawing mode, pass touches to scroll view for zoom
            super.touchesCancelled(touches, with: event)
            return 
        }
        isDrawing = false
        currentPath = []
        setNeedsDisplay()
    }
    
    // Override hitTest to allow scroll view to receive touches when not in drawing mode
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if isDrawingMode {
            // In drawing mode, handle touches for drawing
            return super.hitTest(point, with: event)
        } else {
            // Not in drawing mode, let scroll view handle touches for zoom
            let hitView = super.hitTest(point, with: event)
            if hitView == self {
                return nil // Don't intercept touches, let them pass to scroll view
            }
            return hitView
        }
    }
    
    // Override point(inside:) to control touch handling
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if isDrawingMode {
            // In drawing mode, accept all touches
            return super.point(inside: point, with: event)
        } else {
            // Not in drawing mode, don't intercept touches
            return false
        }
    }
    
    // Simplified coordinate conversion
    private func convertTouchToImageCoordinates(touch: CGPoint) -> CGPoint {
        guard let scrollView = scrollView, let imageView = imageView, let image = originalImage else { 
            return .zero 
        }
        
        let zoomScale = scrollView.zoomScale
        
        // Convert touch point to scroll view content coordinates (accounting for zoom and scroll)
        let contentPoint = CGPoint(
            x: (touch.x + scrollView.contentOffset.x) / zoomScale,
            y: (touch.y + scrollView.contentOffset.y) / zoomScale
        )
        
        // Convert to image view coordinates
        let imageViewFrame = imageView.frame
        let imageViewPoint = CGPoint(
            x: contentPoint.x - imageViewFrame.origin.x / zoomScale,
            y: contentPoint.y - imageViewFrame.origin.y / zoomScale
        )
        
        // Get the actual image bounds within the image view
        let imageViewBounds = imageView.bounds
        let imageSize = image.size
        
        // Calculate the scale factors for aspect fit
        let scaleX = imageViewBounds.width / imageSize.width
        let scaleY = imageViewBounds.height / imageSize.height
        let scale = min(scaleX, scaleY) // scaleAspectFit uses the smaller scale
        
        // Calculate the actual image frame within the image view
        let scaledImageWidth = imageSize.width * scale
        let scaledImageHeight = imageSize.height * scale
        let imageX = (imageViewBounds.width - scaledImageWidth) / 2
        let imageY = (imageViewBounds.height - scaledImageHeight) / 2
        let imageFrame = CGRect(x: imageX, y: imageY, width: scaledImageWidth, height: scaledImageHeight)
        
        // Check if touch is within the image bounds
        guard imageFrame.contains(imageViewPoint) else {
            return .zero
        }
        
        // Convert to image coordinates
        let relativeX = (imageViewPoint.x - imageFrame.origin.x) / imageFrame.width
        let relativeY = (imageViewPoint.y - imageFrame.origin.y) / imageFrame.height
        
        let imageX_coord = relativeX * imageSize.width
        let imageY_coord = relativeY * imageSize.height
        
        return CGPoint(
            x: max(0, min(imageSize.width, imageX_coord)),
            y: max(0, min(imageSize.height, imageY_coord))
        )
    }
    
    // Convert image coordinates to screen coordinates for drawing
    private func convertImageToScreenCoordinates(imagePoint: CGPoint) -> CGPoint {
        guard let scrollView = scrollView, let imageView = imageView, let image = originalImage else { 
            return .zero 
        }
        
        let zoomScale = scrollView.zoomScale
        
        let imageViewBounds = imageView.bounds
        let imageSize = image.size
        
        // Calculate the scale factors for aspect fit
        let scaleX = imageViewBounds.width / imageSize.width
        let scaleY = imageViewBounds.height / imageSize.height
        let scale = min(scaleX, scaleY) // scaleAspectFit uses the smaller scale
        
        // Calculate the actual image frame within the image view
        let scaledImageWidth = imageSize.width * scale
        let scaledImageHeight = imageSize.height * scale
        let imageX = (imageViewBounds.width - scaledImageWidth) / 2
        let imageY = (imageViewBounds.height - scaledImageHeight) / 2
        let imageFrame = CGRect(x: imageX, y: imageY, width: scaledImageWidth, height: scaledImageHeight)
        
        // Convert from image coordinates to image view coordinates
        let relativeX = imagePoint.x / imageSize.width
        let relativeY = imagePoint.y / imageSize.height
        
        let imageViewPoint = CGPoint(
            x: imageFrame.origin.x + (relativeX * imageFrame.width),
            y: imageFrame.origin.y + (relativeY * imageFrame.height)
        )
        
        // Convert to scroll view content coordinates
        let imageViewFrame = imageView.frame
        let contentPoint = CGPoint(
            x: imageViewPoint.x + imageViewFrame.origin.x,
            y: imageViewPoint.y + imageViewFrame.origin.y
        )
        
        // Apply zoom scale
        let zoomedPoint = CGPoint(
            x: contentPoint.x * zoomScale,
            y: contentPoint.y * zoomScale
        )
        
        // Convert to screen coordinates (accounting for scroll offset)
        let screenPoint = CGPoint(
            x: zoomedPoint.x - scrollView.contentOffset.x,
            y: zoomedPoint.y - scrollView.contentOffset.y
        )
        
        return screenPoint
    }
    
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        // Draw existing paths
        for path in blurPaths {
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(3.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            if let firstPoint = path.points.first {
                let screenPoint = convertImageToScreenCoordinates(imagePoint: firstPoint)
                context.move(to: screenPoint)
                for point in path.points.dropFirst() {
                    let screenPoint = convertImageToScreenCoordinates(imagePoint: point)
                    context.addLine(to: screenPoint)
                }
            }
            context.strokePath()
        }
        
        // Draw current path
        if !currentPath.isEmpty {
            context.setStrokeColor(UIColor.red.cgColor)
            context.setLineWidth(3.0)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            
            if let firstPoint = currentPath.first {
                let screenPoint = convertImageToScreenCoordinates(imagePoint: firstPoint)
                context.move(to: screenPoint)
                for point in currentPath.dropFirst() {
                    let screenPoint = convertImageToScreenCoordinates(imagePoint: point)
                    context.addLine(to: screenPoint)
                }
            }
            context.strokePath()
        }
        
        // Draw emoji stickers
        for sticker in emojiStickers {
            let screenPosition = convertImageToScreenCoordinates(imagePoint: sticker.position)
            let attributedString = NSAttributedString(
                string: sticker.emoji,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 40)
                ]
            )
            attributedString.draw(at: screenPosition)
        }
    }
}