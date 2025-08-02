import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import os

private let logger = Logger(subsystem: "com.yourapp.blur", category: "blur")

// MARK: - Theme
struct Theme {
    static let accent = Color(hex: "#6a62da")
    static let background = Color(hex: "#f5f2f1")
    static let card = Color(.systemGray6)
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let buttonCornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
    static let shadow = Color(.black).opacity(0.07)
    static let fontTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let fontSubtitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let fontBody = Font.system(size: 16, weight: .regular, design: .rounded)
}



// MARK: - Main Content View
struct ContentView: View {
    @State private var selectedImage: UIImage?
    @State private var processedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var blurPaths: [BlurPath] = []
    @State private var currentPath: BlurPath?
    @State private var showingShareSheet = false
    @State private var blurRadius: Double = 70 // Default blur radius optimized for new range
    // For real-time adjustment
    @State private var lastBlurredPaths: [BlurPath] = []
    @State private var lastBlurredOriginal: UIImage?
    @State private var blurApplied: Bool = false
    // Video blur screen presentation
    @State private var showVideoBlurScreen = false
    // Drawing out-of-bounds error
    @State private var showDrawError = false
    // Removed showingVideoBlur and all VideoBlurView references
    @State private var showExportSheet = false
    @State private var showSaveSuccess = false
    @State private var isDrawingMode: Bool = false
    @State private var shouldAutoApplyBlur: Bool = false
    

    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topLeading) {
                if selectedImage == nil && processedImage == nil && !showVideoBlurScreen {
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(hex: "#6a62da"), location: 0.0),
                            .init(color: Color.white.opacity(0.7), location: 0.55),
                            .init(color: Color(hex: "#6a62da"), location: 1.0)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 700
                    )
                    .ignoresSafeArea()
                } else {
                    Theme.background.ignoresSafeArea()
                }
                VStack(spacing: 12) { // Reduce overall vertical spacing
                    // Home icon and New Photo button
                    if selectedImage != nil || processedImage != nil {
                        HStack(alignment: .center, spacing: 0) {
                            Button(action: resetApp) {
                                Image(systemName: "house")
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundColor(Theme.accent)
                                    .padding(.leading, 8)
                                    .padding(.top, 8)
                            }
                            .contentShape(Rectangle())
                            Spacer()
                            Button(action: { 
                                // Reset everything and open new photo picker
                                resetToNewPhoto()
                                showingImagePicker = true 
                            }) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(Theme.accent)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(Theme.card)
                                    .cornerRadius(Theme.buttonCornerRadius)
                                    .padding(.trailing, 8)
                                    .padding(.top, 8)
                            }
                            .contentShape(Rectangle())
                        }
                        .zIndex(10)
                        if selectedImage != nil && !blurApplied {
                            HStack {
                                Spacer()
                                Text("DRAW AROUND A FACE TO BLUR")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.primaryText)
                                    .padding(.top, 8)
                                Spacer()
                            }
                        }
                    }
                    if let image = processedImage ?? selectedImage {
                        PhotoEditView(
                            image: image,
                            isDrawingMode: $isDrawingMode,
                            blurPaths: $blurPaths,
                            currentPath: $currentPath,
                            processedImage: $processedImage,
                            originalImage: selectedImage,
                            onAutoApplyBlur: autoApplyBlur
                        )
                        .id("image_\(selectedImage?.hashValue ?? 0)_blur_\(blurApplied)") // Recreate when blur state changes
                
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)

                        // Blur strength slider (move under photo when blur is applied)
                        if blurApplied {
                            VStack(spacing: 8) {
                                Text("Set your desired amount of blur")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.primaryText)
                                Slider(value: $blurRadius, in: 30...80, step: 1, onEditingChanged: { editing in
                                    if !editing {
                                        if let orig = lastBlurredOriginal {
                                            processedImage = BlurProcessor.applyBlur(to: orig, with: lastBlurredPaths, blurRadius: blurRadius)
                                        }
                                    }
                                })
                                .accentColor(Theme.accent)
                                .padding(.horizontal)
                            }
                        }

                        // Different UI based on blur state
                        if blurApplied {
                            // Post-blur UI: Redo and Share buttons
                            VStack(spacing: 16) {
                                Button("Start Again") {
                                    redoDrawing()
                                }
                                .font(.system(size: 18, weight: .semibold))
                                .padding(16)
                                .frame(maxWidth: .infinity)
                                .background(Theme.accent)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .contentShape(Rectangle())
                                
                                Button("Export") {
                                    showExportSheet = true
                                }
                                .font(.system(size: 18, weight: .semibold))
                                .padding(16)
                                .frame(maxWidth: .infinity)
                                .background(Color.green.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .contentShape(Rectangle())
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        } else {
                            // Pre-blur UI: Drawing controls
                            VStack(spacing: 16) {
                                // Instructions
                                Text("Draw around faces to blur them automatically")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                
                                // Top row: Zoom, Draw, Undo
                                HStack(spacing: 16) {
                                    Button("ZOOM") {
                                        // Switch to zoom mode
                                        isDrawingMode = false
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                                    .background(!isDrawingMode ? Theme.accent : Color.clear)
                                    .foregroundColor(!isDrawingMode ? .white : Theme.primaryText)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(!isDrawingMode ? Color.clear : Color.black, lineWidth: 2)
                                    )
                                    .contentShape(Rectangle())
                                    
                                    Button("DRAW") {
                                        // Switch to draw mode
                                        isDrawingMode = true
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                                    .background(isDrawingMode ? Theme.accent : Color.clear)
                                    .foregroundColor(isDrawingMode ? .white : Theme.primaryText)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isDrawingMode ? Color.clear : Color.black, lineWidth: 2)
                                    )
                                    .contentShape(Rectangle())
                                    
                                    Button("UNDO") {
                                        undoLastPath()
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 24)
                                    .background(Color.clear)
                                    .foregroundColor(blurPaths.isEmpty ? Color.gray : Theme.primaryText)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(blurPaths.isEmpty ? Color.gray : Color.black, lineWidth: 2)
                                    )
                                    .disabled(blurPaths.isEmpty)
                                    .contentShape(Rectangle())
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    } else {
                        EmptyStateView(showingImagePicker: $showingImagePicker, showVideoBlurScreen: $showVideoBlurScreen)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    // Remove BottomControlsView since buttons are now in PhotoEditView
                }
                .padding()
                // Centered export modal
                if showExportSheet {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(1)
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            ExportPopupModal(
                                onSave: {
                                    if let image = processedImage {
                                        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                                        showSaveSuccess = true
                                    }
                                    showExportSheet = false
                                },
                                onShare: {
                                    showExportSheet = false
                                    showShareSheetDelayed()
                                },
                                onCancel: { showExportSheet = false }
                            )
                            .frame(maxWidth: 340)
                            Spacer()
                        }
                        Spacer()
                    }
                    .zIndex(2)
                    .transition(.scale)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(selectedImage: $selectedImage, onImageSelected: onImageSelected)
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = processedImage {
                ShareSheet(activityItems: [image])
                    .onAppear {
                        print("[DEBUG] Presenting ShareSheet with image")
                    }
            } else {
                Text("No image available")
                    .onAppear {
                        print("[DEBUG] ERROR: No processedImage available for sharing")
                    }
            }
        }

        .sheet(isPresented: $showVideoBlurScreen) {
            VideoBlurScreen()
        }
        .alert(isPresented: $showDrawError) {
            Alert(title: Text("Drawing Error"),
                  message: Text("Please draw only within the photo preview area."),
                  dismissButton: .default(Text("OK")))
        }
        .alert(isPresented: $showSaveSuccess) {
            Alert(title: Text("Saved!"), message: Text("Image saved to your device."), dismissButton: .default(Text("OK")))
        }
    }
    
    private func onImageSelected() {
        // Reset all state when new image is selected
        blurPaths = []
        currentPath = nil
        processedImage = nil
        lastBlurredPaths = []
        lastBlurredOriginal = nil
        blurApplied = false
        isDrawingMode = false
        
        // Force zoom reset in PhotoEditView by updating the id
        // The id change will force PhotoEditView to recreate and reset zoom
    }
    
    private func resetApp() {
        selectedImage = nil
        processedImage = nil
        blurPaths = []
        currentPath = nil
        blurApplied = false
        lastBlurredPaths = []
        lastBlurredOriginal = nil
        showingImagePicker = false
        showingShareSheet = false
        showVideoBlurScreen = false
        showDrawError = false
        isDrawingMode = false
    }
    
    private func applyBlur() {
        guard let originalImage = selectedImage, !blurPaths.isEmpty else {
            showDrawError = true
            return
        }
        let pathsCopy = blurPaths.map { BlurPath(points: $0.points) } // Deep copy
        lastBlurredPaths = pathsCopy
        lastBlurredOriginal = originalImage
        processedImage = BlurProcessor.applyBlur(to: originalImage, with: pathsCopy, blurRadius: blurRadius)
        blurApplied = true
        blurPaths = []
        currentPath = nil
        isDrawingMode = false // Disable drawing after blur
    }
    
    private func autoApplyBlur(for completedPath: BlurPath) {
        guard let originalImage = selectedImage else { return }
        
        // Create a single path array with the completed path
        let singlePath = [completedPath]
        lastBlurredPaths = singlePath
        lastBlurredOriginal = originalImage
        processedImage = BlurProcessor.applyBlur(to: originalImage, with: singlePath, blurRadius: blurRadius)
        blurApplied = true
        blurPaths = [] // Clear the paths since blur is applied
        currentPath = nil
        isDrawingMode = false // Switch back to zoom mode
    }
    
    private func showShareSheetDelayed() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            showingShareSheet = true
        }
    }

    // Add a new function to clear only the drawn paths
    private func clearDrawnPaths() {
        processedImage = nil
        blurApplied = false
        blurPaths.removeAll()
        currentPath = nil
    }
    
    // Add undo function to remove the last drawn path
    private func undoLastPath() {
        if !blurPaths.isEmpty {
            blurPaths.removeLast()
            currentPath = nil
        }
    }
    
    // Reset everything for new photo selection
    private func resetToNewPhoto() {
        selectedImage = nil
        processedImage = nil
        blurPaths = []
        currentPath = nil
        blurApplied = false
        lastBlurredPaths = []
        lastBlurredOriginal = nil
        isDrawingMode = false
        showingShareSheet = false
        showDrawError = false
        showExportSheet = false
    }
    
    // Clear all drawings at any point
    private func clearAllDrawings() {
        blurPaths.removeAll()
        currentPath = nil
        // If we had blur applied, reset to original image
        if blurApplied {
            processedImage = nil
            blurApplied = false
            lastBlurredPaths = []
            lastBlurredOriginal = nil
        }
    }
    
    // Start Again function - reset to initial state with original image
    private func redoDrawing() {
        if let original = lastBlurredOriginal {
            selectedImage = original
            blurPaths = []
            currentPath = nil
            processedImage = nil
            blurApplied = false
            isDrawingMode = false
            lastBlurredPaths = []
            lastBlurredOriginal = nil
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    @Binding var showingImagePicker: Bool
    @Binding var showVideoBlurScreen: Bool
    var body: some View {
        VStack(spacing: 12) {
            Image("Transparent Baby")
                .resizable()
                .scaledToFit()
                .frame(width: 240, height: 240)
            VStack(spacing: 6) {
                Text("Blur Your Bub")
                    .font(Font.custom("ClashDisplayVariable-Bold_Semibold", size: 36))
                    .foregroundColor(.white)
                Text("Select a photo or video to begin!")
                    .font(Theme.fontBody)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Button(action: { showingImagePicker = true }) {
                HStack {
                    Image(systemName: "photo")
                    Text("Choose Photo")
                }
                .font(Theme.fontSubtitle)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.accent)
                .foregroundColor(.white)
                .cornerRadius(Theme.buttonCornerRadius)
                .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 24)
            Button(action: { showVideoBlurScreen = true }) {
                HStack {
                    Image(systemName: "video.fill")
                    Text("Choose Video")
                }
                .font(Theme.fontSubtitle)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.accent)
                .foregroundColor(.white)
                .cornerRadius(Theme.buttonCornerRadius)
                .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
            }
            .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.top, 24)
    }
}

// MARK: - Bottom Controls
struct BottomControlsView: View {
    let hasImage: Bool
    @Binding var showingImagePicker: Bool
    @Binding var showingShareSheet: Bool
    let processedImage: UIImage?
    let onReset: () -> Void
    let onUndo: () -> Void
    let onApplyBlur: () -> Void
    @Binding var blurApplied: Bool
    var onExport: (() -> Void)? = nil
    let canUndo: Bool

    var body: some View {
        if hasImage {
            VStack(spacing: 20) {
                // Main action buttons (Apply Blur / Export)
                if !blurApplied {
                    Button(action: onApplyBlur) {
                        Text("Apply Blur")
                            .font(Theme.fontBody.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(Theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.buttonCornerRadius + 8)
                            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                    }
                    .disabled(processedImage != nil)
                    .opacity(processedImage != nil ? 0.5 : 1)
                }
                if processedImage != nil {
                    Button(action: { onExport?() }) {
                        Text("Export")
                            .font(Theme.fontBody.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(Theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.buttonCornerRadius + 8)
                            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                    }
                }
                
                // Bottom row with Undo and Clear All
                HStack(spacing: 16) {
                    Button(action: onReset) {
                        Text("Clear All")
                            .font(Theme.fontBody)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(Theme.card)
                            .foregroundColor(Theme.accent)
                            .cornerRadius(Theme.buttonCornerRadius)
                    }
                    
                    Button(action: onUndo) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: 16, weight: .medium))
                            Text("Undo")
                                .font(Theme.fontBody)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.card)
                        .foregroundColor(canUndo ? Theme.accent : Theme.accent.opacity(0.3))
                        .cornerRadius(Theme.buttonCornerRadius)
                    }
                    .disabled(!canUndo)
                }
            }
            .padding(.horizontal, 8)
        }
    }
}

// MARK: - Data Models
// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    let onImageSelected: () -> Void
    @Environment(\.presentationMode) var presentationMode
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if let result = results.first {
                result.itemProvider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image as? UIImage
                        self.parent.onImageSelected()
                    }
                }
            }
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Blur Processor
struct BlurProcessor {
    static func applyBlur(to image: UIImage, with paths: [BlurPath], blurRadius: Double = 150.0) -> UIImage {
        logger.debug("=== BLUR PROCESS START ===")
        logger.debug("Input image size: \(image.size.width) x \(image.size.height)")
        logger.debug("Number of paths: \(paths.count)")
        logger.debug("Blur radius: \(blurRadius)")
        
        let maxDimension: CGFloat = 1024
        let downscaledImage = image.downscaled(maxDimension: maxDimension)
        logger.debug("Downscaled image size: \(downscaledImage.size.width) x \(downscaledImage.size.height)")
        
        let scaleX = downscaledImage.size.width / image.size.width
        let scaleY = downscaledImage.size.height / image.size.height
        logger.debug("Scale factors - X: \(scaleX), Y: \(scaleY)")
        
        let scaledPaths = scalePaths(paths, scaleX: scaleX, scaleY: scaleY)
        logger.debug("Scaled paths count: \(scaledPaths.count)")
        
        guard !scaledPaths.isEmpty else {
            logger.error("No paths to blur - returning original image")
            return downscaledImage
        }
        
        logger.debug("Starting blur process with \(scaledPaths.count) paths")
        guard let cgImage = downscaledImage.cgImage else {
            logger.error("Failed to get CGImage from downscaled image")
            return downscaledImage
        }
        
        guard let context = createBitmapContext(for: downscaledImage) else {
            logger.error("Failed to create context")
            return downscaledImage
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: Int(downscaledImage.size.width), height: Int(downscaledImage.size.height)))
        logger.debug("Original image drawn to context")
        
        guard let blurredCGImage = createBlurredImage(from: cgImage, blurRadius: blurRadius, size: downscaledImage.size) else {
            logger.error("Failed to create blurred CGImage")
            return downscaledImage
        }
        logger.debug("Blurred image created successfully")
        
        let maskImage = createAdvancedMask(from: scaledPaths, imageSize: downscaledImage.size)
        logger.debug("Mask image created, size: \(maskImage.size.width) x \(maskImage.size.height)")

        // Ensure mask is the same size as the images
        let resizedMaskImage = maskImage.resized(to: downscaledImage.size)
        logger.debug("Resized mask image, size: \(resizedMaskImage.size.width) x \(resizedMaskImage.size.height)")

        guard let maskCGImage = resizedMaskImage.cgImage else {
            logger.error("Failed to create mask CGImage")
            return downscaledImage
        }
        logger.debug("Mask CGImage created successfully")
        
        let result = applyMaskToImages(original: cgImage, blurred: blurredCGImage, mask: maskCGImage, size: downscaledImage.size)
        if result != nil {
            logger.debug("=== BLUR PROCESS SUCCESS ===")
        } else {
            logger.error("=== BLUR PROCESS FAILED - applyMaskToImages returned nil ===")
        }
        return result ?? downscaledImage
    }

    private static func scalePaths(_ paths: [BlurPath], scaleX: CGFloat, scaleY: CGFloat) -> [BlurPath] {
        return paths.map { path in
            BlurPath(points: path.points.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) })
        }
    }

    private static func createBitmapContext(for image: UIImage) -> CGContext? {
        let width = Int(image.size.width)
        let height = Int(image.size.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }

    private static func createBlurredImage(from cgImage: CGImage, blurRadius: Double, size: CGSize) -> CGImage? {
        logger.debug("Creating blurred image with radius: \(blurRadius)")
        let ciContext = CIContext()
        let inputImage = CIImage(cgImage: cgImage)
        logger.debug("Input CIImage created")
        
        let blurFilter = CIFilter.gaussianBlur()
        blurFilter.inputImage = inputImage
        blurFilter.radius = Float(blurRadius)
        logger.debug("Blur filter configured with radius: \(blurRadius)")
        
        guard let blurredCIImage = blurFilter.outputImage else { 
            logger.error("Blur filter output is nil")
            return nil 
        }
        logger.debug("Blur filter output created successfully")
        
        let blurredRect = CGRect(origin: .zero, size: size)
        let result = ciContext.createCGImage(blurredCIImage, from: blurredRect)
        if result != nil {
            logger.debug("Blurred CGImage created successfully")
        } else {
            logger.error("Failed to create blurred CGImage from CIImage")
        }
        return result
    }

    private static func createAdvancedMask(from paths: [BlurPath], imageSize: CGSize) -> UIImage {
        logger.debug("=== MASK CREATION START ===")
        logger.debug("Creating mask for \(paths.count) paths")
        logger.debug("Mask image size: \(imageSize.width) x \(imageSize.height)")
        
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let dotRadius = min(imageSize.width, imageSize.height) * 0.05 // Radius for single-point dots
        logger.debug("Dot radius for single points: \(dotRadius)")
        
        let maskImage = renderer.image { context in
            let cgContext = context.cgContext
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: imageSize))
            logger.debug("Mask background filled with black")
            
            cgContext.setFillColor(UIColor.white.cgColor)
            
            for (pathIndex, path) in paths.enumerated() {
                logger.debug("Drawing path \(pathIndex) with \(path.points.count) points")
                guard !path.points.isEmpty else { continue }
                
                if path.points.count == 1 {
                    let point = path.points[0]
                    logger.debug("Drawing single point at (\(point.x), \(point.y)) with radius \(dotRadius)")
                    cgContext.fillEllipse(in: CGRect(
                        x: point.x - dotRadius,
                        y: point.y - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    ))
                } else {
                    let first = path.points.first!
                    logger.debug("Drawing path from (\(first.x), \(first.y)) with \(path.points.count) points")
                    cgContext.beginPath()
                    cgContext.move(to: first)
                    for point in path.points.dropFirst() {
                        cgContext.addLine(to: point)
                    }
                    // Close the path to create an enclosed area and fill it
                    cgContext.closePath()
                    cgContext.fillPath()
                    logger.debug("Path \(pathIndex) filled with white")
                }
            }
        }
        
        // Debug: Print average mask value
        if let cgImage = maskImage.cgImage,
           let data = cgImage.dataProvider?.data,
           let ptr = CFDataGetBytePtr(data) {
            let length = CFDataGetLength(data)
            var total: Int = 0
            var whitePixels: Int = 0
            for i in stride(from: 0, to: length, by: 4) {
                let redValue = Int(ptr[i])
                total += redValue
                if redValue > 200 { // Count pixels that are mostly white
                    whitePixels += 1
                }
            }
            let avg = Double(total) / Double(length / 4)
            let whitePixelPercentage = Double(whitePixels) / Double(length / 4) * 100
            logger.debug("Mask analysis - Average red value: \(avg), White pixels (>200): \(whitePixels) (\(whitePixelPercentage)%)")
        }
        
        logger.debug("=== MASK CREATION COMPLETE ===")
        return maskImage
    }
    
    private static func applyMaskToImages(original: CGImage, blurred: CGImage, mask: CGImage, size: CGSize) -> UIImage? {
        logger.debug("=== MASK APPLICATION START ===")
        logger.debug("Original image size: \(original.width) x \(original.height)")
        logger.debug("Blurred image size: \(blurred.width) x \(blurred.height)")
        logger.debug("Mask image size: \(mask.width) x \(mask.height)")
        
        let width = original.width
        let height = original.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        // Create contexts for all images
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let originalData = CFDataCreateMutable(nil, width * height * bytesPerPixel),
              let blurredData = CFDataCreateMutable(nil, width * height * bytesPerPixel),
              let maskData = CFDataCreateMutable(nil, width * height * bytesPerPixel),
              let outputData = CFDataCreateMutable(nil, width * height * bytesPerPixel) else {
            logger.error("Failed to create data buffers")
            return nil
        }
        
        // Create contexts
        guard let originalContext = CGContext(data: CFDataGetMutableBytePtr(originalData), width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let blurredContext = CGContext(data: CFDataGetMutableBytePtr(blurredData), width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let maskContext = CGContext(data: CFDataGetMutableBytePtr(maskData), width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let outputContext = CGContext(data: CFDataGetMutableBytePtr(outputData), width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            logger.error("Failed to create contexts")
            return nil
        }
        
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        
        // Draw images to contexts
        originalContext.draw(original, in: rect)
        blurredContext.draw(blurred, in: rect)
        maskContext.draw(mask, in: rect)
        logger.debug("All images drawn to contexts")
        
        // Get pixel data
        guard let originalPixels = CFDataGetMutableBytePtr(originalData),
              let blurredPixels = CFDataGetMutableBytePtr(blurredData),
              let maskPixels = CFDataGetMutableBytePtr(maskData),
              let outputPixels = CFDataGetMutableBytePtr(outputData) else {
            logger.error("Failed to get pixel data pointers")
            return nil
        }
        
        logger.debug("Starting pixel blending for \(width * height) pixels")
        
        // Blend pixels based on mask
        var totalMaskValue: Float = 0
        var pixelsWithMask: Int = 0
        var maxMaskValue: Float = 0
        var sampleBlendValues: [(original: UInt8, blurred: UInt8, mask: Float, output: UInt8)] = []

        for i in 0..<(width * height) {
            let pixelIndex = i * 4
            
            // Get mask value (using red channel as grayscale)
            let maskValue = Float(maskPixels[pixelIndex]) / 255.0
            totalMaskValue += maskValue
            maxMaskValue = max(maxMaskValue, maskValue)
            
            if maskValue > 0.1 { // Count pixels with significant mask value
                pixelsWithMask += 1
                
                // Sample a few blend values for debugging
                if sampleBlendValues.count < 5 {
                    let originalRed = originalPixels[pixelIndex]
                    let blurredRed = blurredPixels[pixelIndex]
                    let outputRed = UInt8(Float(originalRed) * (1 - maskValue) + Float(blurredRed) * maskValue)
                    sampleBlendValues.append((original: originalRed, blurred: blurredRed, mask: maskValue, output: outputRed))
                }
            }
            
            // Blend original and blurred based on mask
            outputPixels[pixelIndex] = UInt8(Float(originalPixels[pixelIndex]) * (1 - maskValue) + Float(blurredPixels[pixelIndex]) * maskValue) // Red
            outputPixels[pixelIndex + 1] = UInt8(Float(originalPixels[pixelIndex + 1]) * (1 - maskValue) + Float(blurredPixels[pixelIndex + 1]) * maskValue) // Green
            outputPixels[pixelIndex + 2] = UInt8(Float(originalPixels[pixelIndex + 2]) * (1 - maskValue) + Float(blurredPixels[pixelIndex + 2]) * maskValue) // Blue
            outputPixels[pixelIndex + 3] = originalPixels[pixelIndex + 3] // Alpha
        }
        
        let avgMaskValue = totalMaskValue / Float(width * height)
        logger.debug("Mask statistics - Average: \(avgMaskValue), Max: \(maxMaskValue), Pixels with mask > 0.1: \(pixelsWithMask)")
        logger.debug("Sample blend values: \(sampleBlendValues)")
        
        // Create final image
        guard let finalCGImage = outputContext.makeImage() else {
            logger.error("Failed to create final CGImage")
            return nil
        }
        
        logger.debug("Final image created successfully")
        return UIImage(cgImage: finalCGImage, scale: size.width > 1000 ? 2.0 : 1.0, orientation: .up)
    }
}

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxDimension else { return self }
        let scale = maxDimension / maxSide
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: newSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? self
    }
    
    func resized(to targetSize: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        self.draw(in: CGRect(origin: .zero, size: targetSize))
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage ?? self
    }
}

// Add Color extension for hex support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// New ExportActionSheet
struct ExportActionSheet: View {
    let onSave: () -> Void
    let onShare: () -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                Text("Export Image")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.primaryText)
                Button(action: onSave) {
                    Text("Save image to device")
                        .font(Theme.fontSubtitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.buttonCornerRadius)
                }
                Button(action: onShare) {
                    Text("Share")
                        .font(Theme.fontSubtitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.card)
                        .foregroundColor(Theme.accent)
                        .cornerRadius(Theme.buttonCornerRadius)
                }
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(Theme.fontBody)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(24)
            .background(Theme.background)
            .cornerRadius(28)
            .shadow(color: Theme.shadow, radius: 16, x: 0, y: -4)
            .padding(.horizontal, 8)
        }
        .ignoresSafeArea()
    }
}

// New ExportPopupModal
struct ExportPopupModal: View {
    let onSave: () -> Void
    let onShare: () -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.down")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundColor(Theme.accent)
                    .padding(.top, 16)
                Text("Export Image")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.primaryText)
                Button(action: onSave) {
                    Text("Save image to device")
                        .font(Theme.fontSubtitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.buttonCornerRadius)
                }
                Button(action: onShare) {
                    Text("Share")
                        .font(Theme.fontSubtitle)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.buttonCornerRadius)
                }
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(Theme.fontBody)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
            .padding(28)
            .background(Color.white)
            .cornerRadius(32)
            .shadow(color: Theme.shadow, radius: 24, x: 0, y: 8)
            .frame(maxWidth: 340)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.scale)
        .animation(.spring(), value: 1)
    }
}
