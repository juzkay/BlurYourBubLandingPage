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
struct PhotoEditView: View {
    let image: UIImage
    @Binding var isDrawingMode: Bool
    @Binding var blurPaths: [BlurPath]
    @Binding var currentPath: BlurPath?
    @Binding var processedImage: UIImage?
    let originalImage: UIImage?
    let onAutoApplyBlur: ((BlurPath) -> Void)?
    @Binding var shouldResetZoom: Bool

    var body: some View {
        ZoomablePhotoEditor(
            image: image,
            blurPaths: $blurPaths,
            currentPath: $currentPath,
            isDrawingMode: $isDrawingMode,
            onAutoApplyBlur: onAutoApplyBlur,
            shouldResetZoom: $shouldResetZoom
        )
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - ZoomablePhotoEditor (UIViewRepresentable)
struct ZoomablePhotoEditor: UIViewRepresentable {
    let image: UIImage
    @Binding var blurPaths: [BlurPath]
    @Binding var currentPath: BlurPath?
    @Binding var isDrawingMode: Bool
    let onAutoApplyBlur: ((BlurPath) -> Void)?
    @Binding var shouldResetZoom: Bool
    
    private var imageHash: Int {
        image.pngData()?.hashValue ?? 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        print("[DEBUG] makeUIView called - creating new PhotoEditView")
        // Reset scroll view configuration when creating new view
        context.coordinator.isScrollViewConfigured = false
        let containerView = UIView()
        containerView.backgroundColor = .clear

        // UIScrollView setup
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 0.1
        scrollView.maximumZoomScale = 5.75
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        


        // UIImageView setup
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)

        // Drawing overlay setup
        let drawingOverlay = DrawingOverlayView()
        drawingOverlay.backgroundColor = .clear
        drawingOverlay.isUserInteractionEnabled = true
        drawingOverlay.blurPaths = blurPaths
        drawingOverlay.currentPath = currentPath
        drawingOverlay.scrollView = scrollView
        drawingOverlay.imageView = imageView
        drawingOverlay.originalImage = image
        drawingOverlay.isDrawingMode = isDrawingMode
        drawingOverlay.onPathChanged = { newPaths, newCurrent in
            context.coordinator.updatePaths(newPaths: newPaths, newCurrent: newCurrent)
        }
        drawingOverlay.onAutoApplyBlur = onAutoApplyBlur
        


        // Store references
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.drawingOverlay = drawingOverlay
        context.coordinator.containerView = containerView
        context.coordinator.parent = self
        


        // Add subviews
        containerView.addSubview(scrollView)
        containerView.addSubview(drawingOverlay)

        // Constraints
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            // Remove imageView constraints - we'll handle sizing manually for proper zoom behavior

            drawingOverlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            drawingOverlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            drawingOverlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            drawingOverlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        // This will be configured properly in updateUIView

        // Remove double-tap zoom since user doesn't want it


        // Pass SwiftUI state to coordinator
        context.coordinator.updateBindings(
            blurPaths: $blurPaths,
            currentPath: $currentPath,
            isDrawingMode: $isDrawingMode
        )

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Update coordinator bindings with current SwiftUI state
        context.coordinator.updateBindings(
            blurPaths: $blurPaths,
            currentPath: $currentPath,
            isDrawingMode: $isDrawingMode
        )
        context.coordinator.refreshOverlay()
        
        // Update drawing overlay's drawing mode
        context.coordinator.drawingOverlay?.isDrawingMode = isDrawingMode
        
        // Check if zoom reset is requested
        if shouldResetZoom {
            DispatchQueue.main.async {
                context.coordinator.resetZoomToFitScreen()
            }
        }
        
        // Check if image has changed (original -> processed or vice versa)
        let currentImageHash = imageHash
        if context.coordinator.currentImageHash != currentImageHash {
            context.coordinator.currentImageHash = currentImageHash
            context.coordinator.imageView?.image = image
            context.coordinator.isScrollViewConfigured = false
            
            // Reset zoom to fit screen for new image with proper centering
            DispatchQueue.main.async {
                context.coordinator.setupScrollViewForImage(image: self.image)
            }
        } else {
            // Update the displayed image without resetting zoom
            context.coordinator.imageView?.image = image
        }
        
        // Only setup scroll view if not already configured
        if !context.coordinator.isScrollViewConfigured {
            context.coordinator.setupScrollViewForImage(image: image)
            
            // Fallback setup after layout
            DispatchQueue.main.async {
                if !context.coordinator.isScrollViewConfigured {
                    context.coordinator.setupScrollViewForImage(image: image)
                }
            }
        }
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomablePhotoEditor!
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        weak var drawingOverlay: DrawingOverlayView?
        weak var containerView: UIView?

        // SwiftUI bindings
        var blurPathsBinding: Binding<[BlurPath]>?
        var currentPathBinding: Binding<BlurPath?>?
        var isDrawingModeBinding: Binding<Bool>?

        // Gesture state
        private var isZoomingOrPanning = false
        var isScrollViewConfigured = false
        var currentImageHash: Int = 0

        init(_ parent: ZoomablePhotoEditor) {
            self.parent = parent
        }

        func updateBindings(
            blurPaths: Binding<[BlurPath]>,
            currentPath: Binding<BlurPath?>,
            isDrawingMode: Binding<Bool>
        ) {
            self.blurPathsBinding = blurPaths
            self.currentPathBinding = currentPath
            self.isDrawingModeBinding = isDrawingMode
            drawingOverlay?.blurPaths = blurPaths.wrappedValue
            drawingOverlay?.currentPath = currentPath.wrappedValue
            drawingOverlay?.isDrawingMode = isDrawingMode.wrappedValue
        }

        func updatePaths(newPaths: [BlurPath], newCurrent: BlurPath?) {
            blurPathsBinding?.wrappedValue = newPaths
            currentPathBinding?.wrappedValue = newCurrent
            drawingOverlay?.blurPaths = newPaths
            drawingOverlay?.currentPath = newCurrent
            drawingOverlay?.setNeedsDisplay()
        }

        func refreshOverlay() {
            DispatchQueue.main.async {
                guard let overlay = self.drawingOverlay else { return }
                overlay.blurPaths = self.blurPathsBinding?.wrappedValue ?? []
                overlay.currentPath = self.currentPathBinding?.wrappedValue
                overlay.isDrawingMode = self.isDrawingModeBinding?.wrappedValue ?? false
                overlay.setNeedsDisplay()
            }
        }

        // MARK: - UIScrollViewDelegate
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            isZoomingOrPanning = true
            drawingOverlay?.isDrawingEnabled = false
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            isZoomingOrPanning = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.drawingOverlay?.isDrawingEnabled = self.isDrawingModeBinding?.wrappedValue ?? false
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isZoomingOrPanning = true
            drawingOverlay?.isDrawingEnabled = false
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isZoomingOrPanning = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.drawingOverlay?.isDrawingEnabled = self.isDrawingModeBinding?.wrappedValue ?? false
                }
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isZoomingOrPanning = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.drawingOverlay?.isDrawingEnabled = self.isDrawingModeBinding?.wrappedValue ?? false
            }
        }

        // Double-tap zoom removed per user request
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Don't center during user zoom - let them control the position
        }
        
        func setupScrollViewForImage(image: UIImage) {
            guard let scrollView = scrollView, let imageView = imageView else { return }
            
            // Check if bounds are available, if not, retry after a delay
            guard scrollView.bounds.size.width > 0, scrollView.bounds.size.height > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !self.isScrollViewConfigured {
                        self.setupScrollViewForImage(image: image)
                    }
                }
                return
            }
            
            // Don't setup if already configured
            if isScrollViewConfigured { return }
            
            // Calculate the scale to fit the image in the scroll view with padding
            let scrollViewSize = scrollView.bounds.size
            let imageSize = image.size
            
            // Add padding to ensure image is fully visible
            let paddedSize = CGSize(
                width: scrollViewSize.width * 0.95,  // 5% padding
                height: scrollViewSize.height * 0.95
            )
            
            let widthScale = paddedSize.width / imageSize.width
            let heightScale = paddedSize.height / imageSize.height
            let minScale = min(widthScale, heightScale)
            
            // FORCE RESET EVERYTHING
            scrollView.zoomScale = 1.0
            scrollView.contentOffset = .zero
            scrollView.contentInset = .zero
            
            // Set imageView to full image size
            imageView.frame = CGRect(origin: .zero, size: imageSize)
            
            // Set contentSize to full image size
            scrollView.contentSize = imageSize
            
            // Set zoom scales
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = minScale * 3.45
            
            // Set zoom to fit-to-screen with padding
            scrollView.setZoomScale(minScale, animated: false)
            
            // Center the content only when first loading the image
            centerContent()
            
            isScrollViewConfigured = true
        }
        
        func resetZoomToFitScreen() {
            guard let scrollView = scrollView, let imageView = imageView else { return }
            
            let scrollViewSize = scrollView.bounds.size
            let imageSize = imageView.image?.size ?? CGSize.zero
            
            // Add padding for better visibility
            let paddedSize = CGSize(
                width: scrollViewSize.width * 0.95,
                height: scrollViewSize.height * 0.95
            )
            
            let widthScale = paddedSize.width / imageSize.width
            let heightScale = paddedSize.height / imageSize.height
            let minScale = min(widthScale, heightScale)
            
            scrollView.setZoomScale(minScale, animated: true)
            
            // Center after zoom
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.centerContent()
            }
        }
        
        func centerContent() {
            guard let scrollView = scrollView else { return }
            
            let scrollViewSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize
            
            // Calculate insets to center the content
            let horizontalInset = max(0, (scrollViewSize.width - contentSize.width) / 2)
            let verticalInset = max(0, (scrollViewSize.height - contentSize.height) / 2)
            
            // Apply insets to center content
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
            
            // Reset scroll indicator insets
            scrollView.scrollIndicatorInsets = scrollView.contentInset
        }
        
        // Custom pinch gesture removed - using scroll view's built-in zoom

    }
}

// MARK: - DrawingOverlayView (UIView)
class DrawingOverlayView: UIView {
    var blurPaths: [BlurPath] = []
    var currentPath: BlurPath? = nil
    var scrollView: UIScrollView!
    var imageView: UIImageView!
    var originalImage: UIImage!
    var isDrawingMode: Bool = false {
        didSet { isDrawingEnabled = isDrawingMode }
    }
    var isDrawingEnabled: Bool = true
    var onPathChanged: ((_ newPaths: [BlurPath], _ newCurrent: BlurPath?) -> Void)?
    var onAutoApplyBlur: ((BlurPath) -> Void)?

    private var activePath: BlurPath? = nil
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // When in draw mode, intercept touches for drawing
        // When in zoom mode, let touches pass through to scroll view
        if isDrawingMode && isDrawingEnabled {
            return super.hitTest(point, with: event)
        } else {
            // Let touches pass through to scroll view for zoom/pan when not in drawing mode
            return nil
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled, isDrawingMode, let touch = touches.first else { 
            return 
        }
        
        let point = convertTouchToImageCoordinates(touch: touch.location(in: self))
        activePath = BlurPath(points: [point])
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled, isDrawingMode, let touch = touches.first, var path = activePath else { return }
        
        let point = convertTouchToImageCoordinates(touch: touch.location(in: self))
        path.points.append(point)
        activePath = path
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isDrawingEnabled, isDrawingMode, let path = activePath else { 
            return 
        }
        
        // Complete the path if it has multiple points
        if path.points.count > 1 {
            var newPaths = blurPaths
            newPaths.append(path)
            onPathChanged?(newPaths, nil)
            
            // Automatically apply blur when path is completed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.onAutoApplyBlur?(path) // Call the auto-apply blur callback
            }
        }
        
        activePath = nil
        setNeedsDisplay()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activePath = nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let imageView = imageView, let image = originalImage else { return }
        let context = UIGraphicsGetCurrentContext()
        context?.setLineWidth(12.0)
        context?.setStrokeColor(UIColor.red.withAlphaComponent(0.8).cgColor)
        context?.setLineCap(.round)

        let allPaths = blurPaths + (activePath != nil ? [activePath!] : [])
        for path in allPaths {
            guard path.points.count > 1 else { continue }
            let cgPath = UIBezierPath()
            cgPath.lineWidth = 7.5
            for (i, pt) in path.points.enumerated() {
                let screenPt = convertImageToScreenCoordinates(imagePoint: pt)
                if i == 0 {
                    cgPath.move(to: screenPt)
                } else {
                    cgPath.addLine(to: screenPt)
                }
            }
            cgPath.stroke()
        }
    }

    // MARK: - Coordinate Transformation
    // Follows the formula provided in the prompt
    func convertTouchToImageCoordinates(touch: CGPoint) -> CGPoint {
        guard let scrollView = scrollView, let imageView = imageView, let image = originalImage else { return .zero }
        
        // Get current zoom scale
        let zoomScale = scrollView.zoomScale
        
        // 1. Convert touch point to scroll view content coordinates (accounting for zoom and pan)
        let contentPoint = CGPoint(
            x: (touch.x + scrollView.contentOffset.x) / zoomScale,
            y: (touch.y + scrollView.contentOffset.y) / zoomScale
        )
        
        // 2. Convert to image view coordinates
        let imageViewFrame = imageView.frame
        let imageViewPoint = CGPoint(
            x: contentPoint.x - imageViewFrame.origin.x / zoomScale,
            y: contentPoint.y - imageViewFrame.origin.y / zoomScale
        )
        
        // 3. Convert from image view coordinates to actual image pixels
        // Account for scaleAspectFit scaling
        let imageViewBounds = imageView.bounds
        let imageSize = image.size
        
        // Calculate how the image is scaled within the image view
        let scaleX = imageSize.width / imageViewBounds.width
        let scaleY = imageSize.height / imageViewBounds.height
        let scale = max(scaleX, scaleY) // scaleAspectFit uses the larger scale
        
        // Convert to image coordinates
        let imageX = imageViewPoint.x * scale
        let imageY = imageViewPoint.y * scale
        
        return CGPoint(
            x: max(0, min(imageSize.width, imageX)),
            y: max(0, min(imageSize.height, imageY))
        )
    }

    func convertImageToScreenCoordinates(imagePoint: CGPoint) -> CGPoint {
        guard let scrollView = scrollView, let imageView = imageView, let image = originalImage else { return .zero }
        
        // Get current zoom scale
        let zoomScale = scrollView.zoomScale
        
        // 1. Convert from actual image coordinates to image view coordinates
        // Account for scaleAspectFit scaling
        let imageViewBounds = imageView.bounds
        let imageSize = image.size
        
        // Calculate how the image is scaled within the image view
        let scaleX = imageViewBounds.width / imageSize.width
        let scaleY = imageViewBounds.height / imageSize.height
        let scale = min(scaleX, scaleY) // scaleAspectFit uses the smaller scale
        
        // Convert to image view coordinates
        let imageViewPoint = CGPoint(
            x: imagePoint.x * scale,
            y: imagePoint.y * scale
        )
        
        // 2. Convert to scroll view content coordinates
        let imageViewFrame = imageView.frame
        let contentPoint = CGPoint(
            x: imageViewPoint.x + imageViewFrame.origin.x,
            y: imageViewPoint.y + imageViewFrame.origin.y
        )
        
        // 3. Apply zoom scale
        let zoomedPoint = CGPoint(
            x: contentPoint.x * zoomScale,
            y: contentPoint.y * zoomScale
        )
        
        // 4. Convert to screen coordinates (accounting for scroll offset)
        let screenPoint = CGPoint(
            x: zoomedPoint.x - scrollView.contentOffset.x,
            y: zoomedPoint.y - scrollView.contentOffset.y
        )
        
        return screenPoint
    }
}