import SwiftUI
import UIKit

// MARK: - AIPhotoEditView (SwiftUI wrapper)
struct AIPhotoEditView: View {
    let image: UIImage
    @Binding var detectedFaces: [PhotoDetectedFace]
    @Binding var isPreviewMode: Bool
    let onFaceToggled: (UUID) -> Void

    var body: some View {
        ZoomableAIPhotoEditor(
            image: image,
            detectedFaces: $detectedFaces,
            isPreviewMode: $isPreviewMode,
            onFaceToggled: onFaceToggled
        )
        .cornerRadius(12)
        .padding()
    }
}

// MARK: - ZoomableAIPhotoEditor (UIViewRepresentable)
struct ZoomableAIPhotoEditor: UIViewRepresentable {
    let image: UIImage
    @Binding var detectedFaces: [PhotoDetectedFace]
    @Binding var isPreviewMode: Bool
    let onFaceToggled: (UUID) -> Void
    
    private var imageHash: Int {
        image.pngData()?.hashValue ?? 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear

        // UIScrollView setup
        let scrollView = UIScrollView()
        scrollView.minimumZoomScale = 0.1
        scrollView.maximumZoomScale = 5.0
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

        // Face selection overlay setup
        let faceOverlay = FaceSelectionOverlayView()
        faceOverlay.backgroundColor = .clear
        faceOverlay.isUserInteractionEnabled = true
        faceOverlay.detectedFaces = detectedFaces
        faceOverlay.isPreviewMode = isPreviewMode
        faceOverlay.scrollView = scrollView
        faceOverlay.imageView = imageView
        faceOverlay.originalImage = image
        faceOverlay.onFaceToggled = onFaceToggled
        faceOverlay.translatesAutoresizingMaskIntoConstraints = false

        // Store references
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.faceOverlay = faceOverlay
        context.coordinator.containerView = containerView
        context.coordinator.parent = self

        // Add subviews
        containerView.addSubview(scrollView)
        containerView.addSubview(faceOverlay)

        // Constraints
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            faceOverlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            faceOverlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            faceOverlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            faceOverlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.updateFaces(detectedFaces, isPreviewMode: isPreviewMode)
        
        // Check if image has changed
        let currentImageHash = imageHash
        if context.coordinator.currentImageHash != currentImageHash {
            context.coordinator.currentImageHash = currentImageHash
            context.coordinator.imageView?.image = image
            context.coordinator.isScrollViewConfigured = false
            
            // Reset zoom for new image
            DispatchQueue.main.async {
                context.coordinator.setupScrollViewForImage(image: self.image)
            }
        } else {
            context.coordinator.imageView?.image = image
        }
        
        // Setup scroll view if not configured
        if !context.coordinator.isScrollViewConfigured {
            context.coordinator.setupScrollViewForImage(image: image)
        }
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableAIPhotoEditor!
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        weak var faceOverlay: FaceSelectionOverlayView?
        weak var containerView: UIView?

        var isScrollViewConfigured = false
        var currentImageHash: Int = 0

        init(_ parent: ZoomableAIPhotoEditor) {
            self.parent = parent
        }

        func updateFaces(_ faces: [PhotoDetectedFace], isPreviewMode: Bool) {
            faceOverlay?.detectedFaces = faces
            faceOverlay?.isPreviewMode = isPreviewMode
            faceOverlay?.setNeedsDisplay()
        }

        // MARK: - UIScrollViewDelegate
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            faceOverlay?.setNeedsDisplay()
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            faceOverlay?.setNeedsDisplay()
        }
        
        func setupScrollViewForImage(image: UIImage) {
            guard let scrollView = scrollView, let imageView = imageView else { return }
            
            guard scrollView.bounds.size.width > 0, scrollView.bounds.size.height > 0 else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if !self.isScrollViewConfigured {
                        self.setupScrollViewForImage(image: image)
                    }
                }
                return
            }
            
            if isScrollViewConfigured { return }
            
            let scrollViewSize = scrollView.bounds.size
            let imageSize = image.size
            
            let paddedSize = CGSize(
                width: scrollViewSize.width * 0.95,
                height: scrollViewSize.height * 0.95
            )
            
            let widthScale = paddedSize.width / imageSize.width
            let heightScale = paddedSize.height / imageSize.height
            let minScale = min(widthScale, heightScale)
            
            scrollView.zoomScale = 1.0
            scrollView.contentOffset = .zero
            scrollView.contentInset = .zero
            
            imageView.frame = CGRect(origin: .zero, size: imageSize)
            scrollView.contentSize = imageSize
            
            scrollView.minimumZoomScale = minScale
            scrollView.maximumZoomScale = minScale * 3.0
            
            scrollView.setZoomScale(minScale, animated: false)
            centerContent()
            
            isScrollViewConfigured = true
        }
        
        func centerContent() {
            guard let scrollView = scrollView else { return }
            
            let scrollViewSize = scrollView.bounds.size
            let contentSize = scrollView.contentSize
            
            let horizontalInset = max(0, (scrollViewSize.width - contentSize.width) / 2)
            let verticalInset = max(0, (scrollViewSize.height - contentSize.height) / 2)
            
            scrollView.contentInset = UIEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
            
            scrollView.scrollIndicatorInsets = scrollView.contentInset
        }
    }
}

// MARK: - FaceSelectionOverlayView (UIView)
class FaceSelectionOverlayView: UIView {
    var detectedFaces: [PhotoDetectedFace] = [] {
        didSet { setNeedsDisplay() }
    }
    var isPreviewMode: Bool = false {
        didSet { setNeedsDisplay() }
    }
    var scrollView: UIScrollView!
    var imageView: UIImageView!
    var originalImage: UIImage!
    var onFaceToggled: ((UUID) -> Void)?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Don't allow face selection during preview mode
        guard !isPreviewMode, let touch = touches.first else { return }
        let touchPoint = touch.location(in: self)
        
        // Check which face (if any) was tapped
        for face in detectedFaces {
            let screenRect = convertImageRectToScreenRect(imageRect: face.boundingBox)
            if screenRect.contains(touchPoint) {
                onFaceToggled?(face.id)
                break
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let imageView = imageView, let originalImage = originalImage else { return }
        
        // Don't draw face rectangles during preview mode
        guard !isPreviewMode else { return }
        
        let context = UIGraphicsGetCurrentContext()
        
        for face in detectedFaces {
            let screenRect = convertImageRectToScreenRect(imageRect: face.boundingBox)
            
            // Draw face rectangle
            let color = face.isSelected ? UIColor.systemGreen : UIColor.systemGray
            context?.setStrokeColor(color.cgColor)
            context?.setLineWidth(3.0)
            context?.stroke(screenRect)
            
            // Draw selection indicator
            if face.isSelected {
                context?.setFillColor(UIColor.systemGreen.withAlphaComponent(0.2).cgColor)
                context?.fill(screenRect)
            }
        }
    }

    // MARK: - Coordinate Transformation
    func convertImageRectToScreenRect(imageRect: CGRect) -> CGRect {
        guard let scrollView = scrollView, let imageView = imageView, let originalImage = originalImage else {
            return .zero
        }
        
        let zoomScale = scrollView.zoomScale
        let imageViewFrame = imageView.frame
        let imageSize = originalImage.size
        
        // Calculate the actual displayed image size and position (scaleAspectFit)
        let scaleX = imageViewFrame.width / imageSize.width
        let scaleY = imageViewFrame.height / imageSize.height
        let scale = min(scaleX, scaleY)
        
        let displayedImageWidth = imageSize.width * scale
        let displayedImageHeight = imageSize.height * scale
        
        // Calculate the offset to center the image
        let offsetX = (imageViewFrame.width - displayedImageWidth) / 2
        let offsetY = (imageViewFrame.height - displayedImageHeight) / 2
        
        // Convert image coordinates to image view coordinates
        let imageViewRect = CGRect(
            x: imageRect.origin.x * scale + offsetX,
            y: imageRect.origin.y * scale + offsetY,
            width: imageRect.size.width * scale,
            height: imageRect.size.height * scale
        )
        
        // Convert to screen coordinates (accounting for zoom and scroll)
        let screenRect = CGRect(
            x: (imageViewRect.origin.x + imageViewFrame.origin.x) * zoomScale - scrollView.contentOffset.x,
            y: (imageViewRect.origin.y + imageViewFrame.origin.y) * zoomScale - scrollView.contentOffset.y,
            width: imageViewRect.size.width * zoomScale,
            height: imageViewRect.size.height * zoomScale
        )
        
        return screenRect
    }
}