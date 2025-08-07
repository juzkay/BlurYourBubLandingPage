import SwiftUI
import PhotosUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Combine
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
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var localizationManager = LocalizationManager()
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
    @State private var showingVideoPicker = false
    @State private var selectedVideoURL: URL?

    // Drawing out-of-bounds error
    @State private var showDrawError = false
    // Removed showingVideoBlur and all VideoBlurView references
    @State private var showExportSheet = false
    @State private var showSaveSuccess = false
    @State private var isDrawingMode: Bool = false {
        didSet {
            print("[DEBUG] ContentView - isDrawingMode changed from \(oldValue) to \(isDrawingMode)")
        }
    }
    @State private var shouldAutoApplyBlur: Bool = false
    @State private var showFinalPage: Bool = false
    @State private var shouldResetZoom: Bool = false
    // Settings
    @State private var showSettings = false
    
    // Emoji sticker state
    @State private var emojiStickers: [EmojiSticker] = []
    @State private var selectedEmoji: String = "😀"
    @State private var showEmojiPicker = false
    @State private var isEmojiMode: Bool = false
    

    
    var body: some View {
        NavigationView {
            ZStack(alignment: .topLeading) {
                if selectedImage == nil && processedImage == nil {
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
                VStack(spacing: 4) { // Further reduced overall vertical spacing
                    // Home icon, New Photo button, and Settings
                    if selectedImage != nil || processedImage != nil {
                        HStack(alignment: .center, spacing: 0) {
                            Button(action: resetApp) {
                                Image(systemName: "house")
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundColor(Theme.accent)
                                    .padding(.leading, 8)
                                    .padding(.top, 2)
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
                                    .padding(.top, 2)
                            }
                            .contentShape(Rectangle())
                            
                            Button(action: { showSettings = true }) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(Theme.accent)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(Theme.card)
                                    .cornerRadius(Theme.buttonCornerRadius)
                                    .padding(.trailing, 8)
                                    .padding(.top, 2)
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
                                    .padding(.top, 2)
                                Spacer()
                            }
                        }
                    } else {
                        // Settings button for empty state
                        HStack {
                            Spacer()
                            Button(action: { showSettings = true }) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 24, weight: .regular))
                                    .foregroundColor(Theme.accent)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                            }
                            .contentShape(Rectangle())
                        }
                        .zIndex(10)
                    }
                    if let image = processedImage ?? selectedImage {
                        PhotoEditView(
                            image: image,
                            isDrawingMode: isDrawingMode,
                            blurPaths: blurPaths,
                            emojiStickers: emojiStickers,
                            onPathAdded: { newPath in
                                blurPaths.append(newPath)
                                // Auto-apply blur when path is added
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    autoApplyBlur(for: newPath)
                                }
                            },
                            onEmojiAdded: { newEmoji in
                                emojiStickers.append(newEmoji)
                            }
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: UIScreen.main.bounds.height * 0.6) // Fixed height to prevent movement
                        .background(Color.gray.opacity(0.1)) // Background to stabilize layout
                        .padding(.horizontal, 8) // Reduced padding to make photo area larger
                        .padding(.vertical, 4) // Reduced vertical padding

                        // Blur strength slider (move under photo when blur is applied)
                        if blurApplied || showFinalPage {
                            VStack(spacing: 8) {
                                Text("Set your desired amount of blur")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.primaryText)
                                Slider(value: $blurRadius, in: 30...80, step: 1, onEditingChanged: { editing in
                                    if !editing {
                                        // Only apply blur when user stops dragging to prevent lag
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                            if let orig = lastBlurredOriginal {
                                                var processedImg = BlurProcessor.applyBlur(to: orig, with: lastBlurredPaths, blurRadius: blurRadius)
                                                
                                                // Apply emojis if any exist
                                                if !emojiStickers.isEmpty {
                                                    processedImg = applyEmojisToImage(processedImg)
                                                }
                                                
                                                processedImage = processedImg
                                            }
                                        }
                                    }
                                })
                                .accentColor(Theme.accent)
                                .padding(.horizontal)
                            }
                        }

                        // Different UI based on blur state
                        if blurApplied || showFinalPage {
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
                                // Four buttons row: ZOOM, DRAW, EMOJI, UNDO
                                HStack(spacing: 8) {
                                    Button("ZOOM") {
                                        // Switch to zoom mode
                                        isDrawingMode = false
                                        isEmojiMode = false
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44) // Fixed height for all buttons
                                    .background(!isDrawingMode && !isEmojiMode ? Theme.accent : Color.clear)
                                    .foregroundColor(!isDrawingMode && !isEmojiMode ? .white : Theme.primaryText)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(!isDrawingMode && !isEmojiMode ? Color.clear : Color.black, lineWidth: 2)
                                    )
                                    .contentShape(Rectangle())
                                    
                                    Button("DRAW") {
                                        // Switch to draw mode
                                        isDrawingMode = true
                                        isEmojiMode = false
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44) // Fixed height for all buttons
                                    .background(isDrawingMode ? Theme.accent : Color.clear)
                                    .foregroundColor(isDrawingMode ? .white : Theme.primaryText)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isDrawingMode ? Color.clear : Color.black, lineWidth: 2)
                                    )
                                    .contentShape(Rectangle())
                                    
                                    Button("EMOJI") {
                                        // Switch to emoji mode and auto-apply to blur areas
                                        isDrawingMode = false
                                        isEmojiMode = true
                                        showEmojiPicker = true
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44) // Fixed height for all buttons
                                    .background(isEmojiMode ? Theme.accent : Color.clear)
                                    .foregroundColor(isEmojiMode ? .white : Theme.primaryText)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isEmojiMode ? Color.clear : Color.black, lineWidth: 2)
                                    )
                                    .contentShape(Rectangle())
                                    
                                    Button("UNDO") {
                                        undoLastPath()
                                    }
                                    .font(.system(size: 16, weight: .semibold))
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44) // Fixed height for all buttons
                                    .background(Color.clear)
                                    .foregroundColor(Theme.primaryText)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.black, lineWidth: 2)
                                    )
                                    .contentShape(Rectangle())
                                    .disabled(lastBlurredPaths.isEmpty && emojiStickers.isEmpty)
                                    .opacity(lastBlurredPaths.isEmpty && emojiStickers.isEmpty ? 0.5 : 1.0)
                                }
                                .padding(.top, 16) // Padding above the main button row

                                // Done Button
                                Button("DONE →") {
                                    // Move to final page with blur strength and share options
                                    showFinalPage = true
                                }
                                .font(.system(size: 18, weight: .bold))
                                .padding(18)
                                .frame(maxWidth: .infinity)
                                .background(Theme.accent)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .contentShape(Rectangle())
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)
                        }
                    } else {
                        EmptyStateView(
                            showingImagePicker: $showingImagePicker, 
                            showVideoBlurScreen: $showVideoBlurScreen,
                            showingVideoPicker: $showingVideoPicker,
                            localizationManager: localizationManager
                        )
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

        .fullScreenCover(isPresented: $showVideoBlurScreen) {
            VideoBlurScreen(selectedVideoURL: selectedVideoURL)
        }
        .sheet(isPresented: $showingVideoPicker) {
            ContentVideoPicker { url in
                // When video is selected, store the URL and open the video blur screen
                selectedVideoURL = url
                showVideoBlurScreen = true
            }
        }

        .sheet(isPresented: $showSettings) {
            SettingsView(settingsManager: settingsManager, localizationManager: localizationManager)
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerView(selectedEmoji: $selectedEmoji)
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
        emojiStickers = []
        isEmojiMode = false
        
        // Force zoom reset in PhotoEditView by updating the id
        // The id change will force PhotoEditView to recreate and reset zoom
    }
    
    private func resetApp() {
        selectedImage = nil
        processedImage = nil
        blurPaths = []
        currentPath = nil
        lastBlurredPaths = []
        lastBlurredOriginal = nil
        blurApplied = false
        showingImagePicker = false
        showingShareSheet = false
        showVideoBlurScreen = false
        selectedVideoURL = nil
        showDrawError = false
        isDrawingMode = false
        showFinalPage = false
        emojiStickers = []
        isEmojiMode = false
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
        
        // Add the new path to the existing blurred paths
        if lastBlurredPaths.isEmpty {
            // First blur - start with the completed path
            lastBlurredPaths = [completedPath]
        } else {
            // Subsequent blurs - add to existing paths
            lastBlurredPaths.append(completedPath)
        }
        
        // Clear emoji stickers when new blur is applied
        emojiStickers.removeAll()
        
        lastBlurredOriginal = originalImage
        var processedImg = BlurProcessor.applyBlur(to: originalImage, with: lastBlurredPaths, blurRadius: blurRadius)
        
        // Apply emojis if any exist
        if !emojiStickers.isEmpty {
            processedImg = applyEmojisToImage(processedImg)
        }
        
        processedImage = processedImg
        // Don't set blurApplied = true - stay on drawing page
        blurPaths = [] // Clear the paths since blur is applied
        currentPath = nil
        // Keep drawing mode active so user can continue drawing
        
        // Remove zoom reset after blur is applied to test if this causes movement
        // DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        //     shouldResetZoom = true
        // }
    }
    
    private func resetZoomToFitScreen() {
        // Remove zoom reset functionality to test if this causes movement
        // shouldResetZoom = true
        // DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        //     shouldResetZoom = false
        // }
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
    
    // Add undo function to remove the last drawn path or emoji
    private func undoLastPath() {
        if !lastBlurredPaths.isEmpty {
            lastBlurredPaths.removeLast()
            currentPath = nil
            
            // Clear emoji stickers when blur paths change
            emojiStickers.removeAll()
            
            // Reapply blur with remaining paths
            if let originalImage = lastBlurredOriginal {
                if lastBlurredPaths.isEmpty {
                    // No more blur paths - show original image
                    processedImage = originalImage
                } else {
                    // Reapply blur with remaining paths
                    processedImage = BlurProcessor.applyBlur(to: originalImage, with: lastBlurredPaths, blurRadius: blurRadius)
                }
            }
        } else if !emojiStickers.isEmpty {
            // Remove last emoji sticker
            emojiStickers.removeLast()
        }
    }
    
    // Place emoji sticker on the image
    private func placeEmoji(at position: CGPoint) {
        // If there are blur paths, automatically place emojis over blur areas
        if !lastBlurredPaths.isEmpty {
            // Clear existing emoji stickers
            emojiStickers.removeAll()
            
            // Place emojis over each blur path
            for (index, blurPath) in lastBlurredPaths.enumerated() {
                // Calculate center of blur path
                let centerPoint = calculateBlurPathCenter(blurPath)
                
                // Create emoji sticker at the center of blur area
                let newSticker = EmojiSticker(
                    emoji: selectedEmoji,
                    position: centerPoint,
                    size: calculateEmojiSize(for: blurPath)
                )
                emojiStickers.append(newSticker)
            }
            
            // Remove blur when emoji is applied
            processedImage = selectedImage
            lastBlurredPaths.removeAll()
            lastBlurredOriginal = nil
        } else {
            // If no blur paths, place emoji at the tapped position
            let newSticker = EmojiSticker(emoji: selectedEmoji, position: position)
            emojiStickers.append(newSticker)
        }
    }
    
    // Calculate the center point of a blur path
    private func calculateBlurPathCenter(_ blurPath: BlurPath) -> CGPoint {
        guard !blurPath.points.isEmpty else { return .zero }
        
        let xSum = blurPath.points.reduce(0) { $0 + $1.x }
        let ySum = blurPath.points.reduce(0) { $0 + $1.y }
        
        let centerX = xSum / CGFloat(blurPath.points.count)
        let centerY = ySum / CGFloat(blurPath.points.count)
        
        return CGPoint(x: centerX, y: centerY)
    }
    
    // Calculate appropriate emoji size based on blur path size
    private func calculateEmojiSize(for blurPath: BlurPath) -> CGFloat {
        guard !blurPath.points.isEmpty else { return 60.0 }
        
        // Calculate the bounding box of the blur path
        let xCoords = blurPath.points.map { $0.x }
        let yCoords = blurPath.points.map { $0.y }
        
        let minX = xCoords.min() ?? 0
        let maxX = xCoords.max() ?? 0
        let minY = yCoords.min() ?? 0
        let maxY = yCoords.max() ?? 0
        
        let width = maxX - minX
        let height = maxY - minY
        
        // Use the larger dimension to determine emoji size
        let maxDimension = max(width, height)
        
        // Scale emoji size to cover the entire blur area with some padding
        // Use 1.2x the max dimension to ensure full coverage
        let scaledSize = max(40.0, min(200.0, maxDimension * 1.2))
        
        return scaledSize
    }
    
    // Apply emojis to the processed image
    private func applyEmojisToImage(_ image: UIImage) -> UIImage {
        guard !emojiStickers.isEmpty else { return image }
        
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        // Draw the base image
        image.draw(in: CGRect(origin: .zero, size: image.size))
        
        // Draw emoji stickers
        for sticker in emojiStickers {
            let emojiSize = sticker.size
            let emojiRect = CGRect(
                x: sticker.position.x - emojiSize / 2,
                y: sticker.position.y - emojiSize / 2,
                width: emojiSize,
                height: emojiSize
            )
            
            // Create attributed string for emoji
            let emojiAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: emojiSize)
            ]
            let attributedString = NSAttributedString(string: sticker.emoji, attributes: emojiAttributes)
            
            // Draw emoji
            attributedString.draw(in: emojiRect)
        }
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
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
        showFinalPage = false
        emojiStickers = []
        isEmojiMode = false
    }
    
    // Clear all drawings at any point
    private func clearAllDrawings() {
        blurPaths.removeAll()
        currentPath = nil
        emojiStickers.removeAll()
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
            showFinalPage = false
            shouldResetZoom = true
            emojiStickers = []
            isEmojiMode = false
        } else if let original = selectedImage {
            // If no lastBlurredOriginal, reset to the current selected image
            selectedImage = original
            blurPaths = []
            currentPath = nil
            processedImage = nil
            blurApplied = false
            isDrawingMode = false
            lastBlurredPaths = []
            lastBlurredOriginal = nil
            showFinalPage = false
            shouldResetZoom = true
            emojiStickers = []
            isEmojiMode = false
        }
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    @Binding var showingImagePicker: Bool
    @Binding var showVideoBlurScreen: Bool
    @Binding var showingVideoPicker: Bool
    @ObservedObject var localizationManager: LocalizationManager
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
                    Text(localizationManager.localizedString("Select Photo"))
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
            Button(action: { showingVideoPicker = true }) {
                HStack {
                    Image(systemName: "video.fill")
                    Text(localizationManager.localizedString("Select Video"))
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
    
    // MARK: - Professional Face Blur Method (Industry Standard)
    static func applyBlurToFaces(to image: UIImage, faceRects: [CGRect], blurRadius: Double = 70.0) -> UIImage {
        logger.debug("=== FACE BLUR PROCESS START ===")
        logger.debug("Input image size: \(image.size.width) x \(image.size.height)")
        logger.debug("Number of face rects: \(faceRects.count)")
        logger.debug("Blur radius: \(blurRadius)")
        
        guard !faceRects.isEmpty else {
            logger.debug("No face rects to blur - returning original image")
            return image
        }
        
        let maxDimension: CGFloat = 1024
        let downscaledImage = image.downscaled(maxDimension: maxDimension)
        logger.debug("Downscaled image size: \(downscaledImage.size.width) x \(downscaledImage.size.height)")
        
        let scaleX = downscaledImage.size.width / image.size.width
        let scaleY = downscaledImage.size.height / image.size.height
        logger.debug("Scale factors - X: \(scaleX), Y: \(scaleY)")
        
        let scaledFaceRects = scaleFaceRects(faceRects, scaleX: scaleX, scaleY: scaleY)
        logger.debug("Scaled face rects count: \(scaledFaceRects.count)")
        
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
        
        let maskImage = createFaceMask(from: scaledFaceRects, imageSize: downscaledImage.size)
        logger.debug("Face mask image created, size: \(maskImage.size.width) x \(maskImage.size.height)")

        let resizedMaskImage = maskImage.resized(to: downscaledImage.size)
        logger.debug("Resized face mask image, size: \(resizedMaskImage.size.width) x \(resizedMaskImage.size.height)")

        guard let maskCGImage = resizedMaskImage.cgImage else {
            logger.error("Failed to create mask CGImage")
            return downscaledImage
        }
        logger.debug("Mask CGImage created successfully")
        
        let result = applyMaskToImages(original: cgImage, blurred: blurredCGImage, mask: maskCGImage, size: downscaledImage.size)
        if result != nil {
            logger.debug("=== FACE BLUR PROCESS SUCCESS ===")
        } else {
            logger.error("=== FACE BLUR PROCESS FAILED - applyMaskToImages returned nil ===")
        }
        return result ?? downscaledImage
    }
    
    private static func scaleFaceRects(_ rects: [CGRect], scaleX: CGFloat, scaleY: CGFloat) -> [CGRect] {
        return rects.map { rect in
            CGRect(
                x: rect.origin.x * scaleX,
                y: rect.origin.y * scaleY,
                width: rect.size.width * scaleX,
                height: rect.size.height * scaleY
            )
        }
    }
    
    private static func createFaceMask(from faceRects: [CGRect], imageSize: CGSize) -> UIImage {
        logger.debug("=== FACE MASK CREATION START ===")
        logger.debug("Creating mask for \(faceRects.count) face rectangles")
        logger.debug("Mask image size: \(imageSize.width) x \(imageSize.height)")
        
        // Create mask using explicit syntax to avoid compiler ambiguity
        let maskImage: UIImage
        UIGraphicsBeginImageContextWithOptions(imageSize, false, 1.0)
        
        if let cgContext = UIGraphicsGetCurrentContext() {
            // Fill background with black (no blur)
            cgContext.setFillColor(UIColor.black.cgColor)
            cgContext.fill(CGRect(origin: .zero, size: imageSize))
            logger.debug("Mask background filled with black")
            
            // Fill face rectangles with white (blur these areas)
            cgContext.setFillColor(UIColor.white.cgColor)
            
            for (index, faceRect) in faceRects.enumerated() {
                logger.debug("🏭 Processing professional face mask \(index): \(String(describing: faceRect))")
                
                // PROFESSIONAL: Create natural face-shaped elliptical mask
                let professionalMask = createProfessionalFaceMask(
                    rect: faceRect,
                    imageSize: imageSize,
                    context: cgContext,
                    index: index
                )
                
                if professionalMask {
                    logger.debug("✅ Professional face mask \(index) created successfully")
                } else {
                    logger.debug("❌ Professional face mask \(index) failed - outside bounds")
                }
            }
            
            maskImage = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        } else {
            maskImage = UIImage()
        }
        
        UIGraphicsEndImageContext()
        
        logger.debug("🏭 === PROFESSIONAL FACE MASK CREATION COMPLETE ===")
        return maskImage
    }
    
    // MARK: - Professional Elliptical Face Mask (Industry Standard)
    private static func createProfessionalFaceMask(rect: CGRect, imageSize: CGSize, context: CGContext, index: Int) -> Bool {
        // PROFESSIONAL: Create expanded ellipse for more natural blur coverage
        let expansionFactor: CGFloat = 1.3 // 30% larger for professional coverage
        let expandedWidth = rect.width * expansionFactor
        let expandedHeight = rect.height * expansionFactor
        
        let expandedRect = CGRect(
            x: rect.midX - expandedWidth / 2,
            y: rect.midY - expandedHeight / 2,
            width: expandedWidth,
            height: expandedHeight
        )
        
        // Ensure expanded rect stays within image bounds
        let clampedRect = expandedRect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !clampedRect.isNull && !clampedRect.isEmpty else {
            return false
        }
        
        logger.debug("🏭 Professional face \(index): original=\(String(describing: rect)), expanded=\(String(describing: clampedRect))")
        
        // INDUSTRY STANDARD: Create natural face-shaped ellipse
        // Faces are typically slightly taller than wide
        let faceAspectRatio: CGFloat = 0.8 // Natural face proportions
        let naturalWidth = min(clampedRect.width, clampedRect.height * faceAspectRatio)
        let naturalHeight = naturalWidth / faceAspectRatio
        
        let naturalRect = CGRect(
            x: clampedRect.midX - naturalWidth / 2,
            y: clampedRect.midY - naturalHeight / 2,
            width: naturalWidth,
            height: naturalHeight
        )
        
        // Ensure natural rect is within bounds
        let finalRect = naturalRect.intersection(CGRect(origin: .zero, size: imageSize))
        guard !finalRect.isNull && !finalRect.isEmpty else {
            return false
        }
        
        // PROFESSIONAL: Draw main elliptical mask
        context.setFillColor(UIColor.white.cgColor)
        context.fillEllipse(in: finalRect)
        
        // INDUSTRY STANDARD: Add soft feathered edge for natural transition
        let featherInset = min(finalRect.width, finalRect.height) * 0.15 // 15% feather
        let featherRect = finalRect.insetBy(dx: featherInset, dy: featherInset)
        
        if !featherRect.isNull && !featherRect.isEmpty {
            context.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor)
            context.fillEllipse(in: featherRect)
            
            // Add center soft blend
            let centerInset = featherInset * 0.5
            let centerRect = finalRect.insetBy(dx: centerInset, dy: centerInset)
            if !centerRect.isNull && !centerRect.isEmpty {
                context.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor)
                context.fillEllipse(in: centerRect)
            }
        }
        
        logger.debug("🏭 Professional elliptical mask created: \(String(describing: finalRect))")
        return true
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
    let title: String
    let saveButtonText: String
    
    init(onSave: @escaping () -> Void, onShare: @escaping () -> Void, onCancel: @escaping () -> Void, title: String = "Export Image", saveButtonText: String = "Save image to device") {
        self.onSave = onSave
        self.onShare = onShare
        self.onCancel = onCancel
        self.title = title
        self.saveButtonText = saveButtonText
    }
    
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
                Text(title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.primaryText)
                Button(action: onSave) {
                    Text(saveButtonText)
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

// MARK: - Settings View
struct SettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var localizationManager: LocalizationManager
    @State private var showPhotoSettings = false
    @State private var showVideoSettings = false
    @State private var showLanguagePicker = false
    @State private var showClearCacheAlert = false
    
    let languages = ["English", "Spanish", "French", "German", "Italian", "Portuguese", "Chinese", "Japanese", "Korean"]
    let photoFormats = ["Auto", "HEIF", "JPEG", "PNG"]
    let videoResolutions = ["720p", "1080p", "4K"]
    let videoFrameRates = ["24fps", "30fps", "60fps"]
    let videoFormats = ["MOV", "MP4"]
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        Spacer()
                        Text(localizationManager.localizedString("Settings"))
                            .font(Theme.fontTitle)
                            .foregroundColor(Theme.primaryText)
                        Spacer()
                        // Empty space for balance
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            // Upgrade Section
                            SettingsSection(title: "Premium") {
                                SettingsRow(
                                    icon: "crown.fill",
                                    iconColor: .orange,
                                    title: localizationManager.localizedString("Upgrade to BlurYourBub Pro!"),
                                    subtitle: "Unlock advanced features",
                                    showArrow: true
                                ) {
                                    // Dummy action for upgrade
                                }
                            }
                            
                            // Photo Settings Section
                            SettingsSection(title: localizationManager.localizedString("Photo Settings")) {
                                SettingsRow(
                                    icon: "photo",
                                    iconColor: .green,
                                    title: localizationManager.localizedString("Photo Setting"),
                                    subtitle: settingsManager.photoFormat,
                                    showArrow: true
                                ) {
                                    showPhotoSettings = true
                                }
                            }
                            
                            // Video Settings Section
                            SettingsSection(title: localizationManager.localizedString("Video Settings")) {
                                SettingsRow(
                                    icon: "video.fill",
                                    iconColor: .blue,
                                    title: localizationManager.localizedString("Video Setting"),
                                    subtitle: "\(settingsManager.videoResolution) • \(settingsManager.videoFrameRate) • \(settingsManager.videoFormat)",
                                    showArrow: true
                                ) {
                                    showVideoSettings = true
                                }
                            }
                            
                            // App Settings Section
                            SettingsSection(title: "App Settings") {
                                SettingsRow(
                                    icon: "trash",
                                    iconColor: .gray,
                                    title: localizationManager.localizedString("Clear Cache"),
                                    subtitle: "\(settingsManager.getCacheSize()) • Free up storage space",
                                    showArrow: false
                                ) {
                                    showClearCacheAlert = true
                                }
                                
                                SettingsRow(
                                    icon: "globe",
                                    iconColor: .gray,
                                    title: localizationManager.localizedString("Language"),
                                    subtitle: settingsManager.selectedLanguage,
                                    showArrow: true
                                ) {
                                    showLanguagePicker = true
                                }
                            }
                            
                            // Engagement Section
                            SettingsSection(title: "Support") {
                                SettingsRow(
                                    icon: "star.fill",
                                    iconColor: .yellow,
                                    title: localizationManager.localizedString("Rate us on App Store"),
                                    subtitle: "Help us grow",
                                    showArrow: true
                                ) {
                                    // Open App Store rating
                                }
                                
                                SettingsRow(
                                    icon: "square.and.arrow.up",
                                    iconColor: .gray,
                                    title: localizationManager.localizedString("Invite Friends"),
                                    subtitle: "Share the app",
                                    showArrow: true
                                ) {
                                    // Share app
                                }
                                
                                SettingsRow(
                                    icon: "envelope",
                                    iconColor: .gray,
                                    title: localizationManager.localizedString("Send Feedback"),
                                    subtitle: "Help us improve",
                                    showArrow: true
                                ) {
                                    // Send feedback
                                }
                            }
                            
                            // Legal Section
                            SettingsSection(title: "Legal") {
                                SettingsRow(
                                    icon: "eye",
                                    iconColor: .gray,
                                    title: "Privacy & Terms",
                                    subtitle: "Read our policies",
                                    showArrow: true
                                ) {
                                    // Show privacy & terms
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showPhotoSettings) {
            PhotoSettingsView(settingsManager: settingsManager)
        }
        .sheet(isPresented: $showVideoSettings) {
            VideoSettingsView(settingsManager: settingsManager)
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView(settingsManager: settingsManager, localizationManager: localizationManager)
        }
        .alert(isPresented: $showClearCacheAlert) {
            Alert(
                title: Text(localizationManager.localizedString("Clear Cache")),
                message: Text(localizationManager.localizedString("This will free up storage space by clearing temporary files and cached data.")),
                primaryButton: .destructive(Text(localizationManager.localizedString("Clear Cache"))) {
                    settingsManager.clearCache()
                },
                secondaryButton: .cancel(Text(localizationManager.localizedString("Cancel")))
            )
        }
    }
}

// MARK: - Language Picker View
struct LanguagePickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var localizationManager: LocalizationManager
    @State private var showRestartAlert = false
    @State private var selectedLanguage = ""
    
    let languages = [
        ("English", "English"),
        ("Spanish", "Español"),
        ("French", "Français"),
        ("German", "Deutsch"),
        ("Italian", "Italiano"),
        ("Portuguese", "Português"),
        ("Chinese", "中文"),
        ("Japanese", "日本語"),
        ("Korean", "한국어")
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        Spacer()
                        Text("Language")
                            .font(Theme.fontTitle)
                            .foregroundColor(Theme.primaryText)
                        Spacer()
                        // Empty space for balance
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    VStack(spacing: 0) {
                        VStack(spacing: 0) {
                            ForEach(languages, id: \.0) { language in
                                Button(action: {
                                    selectedLanguage = language.0
                                    settingsManager.saveLanguage(language.0)
                                    showRestartAlert = true
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(language.0)
                                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                                .foregroundColor(Theme.primaryText)
                                            
                                            Text(language.1)
                                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                                .foregroundColor(Theme.secondaryText)
                                        }
                                        
                                        Spacer()
                                        
                                        if settingsManager.selectedLanguage == language.0 {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if language.0 != languages.last?.0 {
                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(Theme.cardCornerRadius)
                        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 2)
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .alert(isPresented: $showRestartAlert) {
            Alert(
                title: Text(localizationManager.localizedString("Language Changed")),
                message: Text(String(format: localizationManager.localizedString("The app language has been changed to %@. Please close and reopen the app to see the changes."), selectedLanguage)),
                primaryButton: .default(Text(localizationManager.localizedString("Close App"))) {
                    // Exit the app to trigger close
                    exit(0)
                },
                secondaryButton: .cancel(Text(localizationManager.localizedString("Later"))) {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Photo Settings View
struct PhotoSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var settingsManager: SettingsManager
    
    let formats = [
        ("Auto", "Automatic format selection"),
        ("HEIF", "Smaller Size"),
        ("JPEG", "Better Compatibility"),
        ("PNG", "Higher Quality")
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        Spacer()
                        Text("Photo Setting")
                            .font(Theme.fontTitle)
                            .foregroundColor(Theme.primaryText)
                        Spacer()
                        // Empty space for balance
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    VStack(spacing: 0) {
                        Text("Saving Format")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(Theme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                            .padding(.bottom, 12)
                        
                        VStack(spacing: 0) {
                            ForEach(formats, id: \.0) { format in
                                Button(action: {
                                    settingsManager.savePhotoFormat(format.0)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(format.0)
                                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                                .foregroundColor(Theme.primaryText)
                                            
                                            if !format.1.isEmpty {
                                                Text(format.1)
                                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                                    .foregroundColor(Theme.secondaryText)
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        if settingsManager.photoFormat == format.0 {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(Theme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                if format.0 != formats.last?.0 {
                                    Divider()
                                        .padding(.leading, 20)
                                }
                            }
                        }
                        .background(Color.white)
                        .cornerRadius(Theme.cardCornerRadius)
                        .shadow(color: Theme.shadow, radius: 8, x: 0, y: 2)
                        .padding(.horizontal, 20)
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Video Settings View
struct VideoSettingsView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var settingsManager: SettingsManager
    
    let resolutions = ["720p", "1080p", "4K"]
    let frameRates = ["24fps", "30fps", "60fps"]
    let formats = ["MOV", "MP4"]
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        Spacer()
                        Text("Video Setting")
                            .font(Theme.fontTitle)
                            .foregroundColor(Theme.primaryText)
                        Spacer()
                        // Empty space for balance
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    VStack(spacing: 24) {
                        // Video Resolution
                        VStack(spacing: 0) {
                            Text("Video Resolution")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.top, 20)
                                .padding(.bottom, 12)
                            
                            VStack(spacing: 0) {
                                ForEach(resolutions, id: \.self) { resolution in
                                    Button(action: {
                                        settingsManager.saveVideoSettings(
                                            resolution: resolution,
                                            frameRate: settingsManager.videoFrameRate,
                                            format: settingsManager.videoFormat
                                        )
                                    }) {
                                        HStack {
                                            Text(resolution)
                                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                                .foregroundColor(Theme.primaryText)
                                            
                                            Spacer()
                                            
                                            if settingsManager.videoResolution == resolution {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundColor(Theme.accent)
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if resolution != resolutions.last {
                                        Divider()
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(Theme.cardCornerRadius)
                            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 2)
                            .padding(.horizontal, 20)
                        }
                        
                        // Frame Rate
                        VStack(spacing: 0) {
                            Text("Frame rate")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                            
                            VStack(spacing: 0) {
                                ForEach(frameRates, id: \.self) { frameRate in
                                    Button(action: {
                                        settingsManager.saveVideoSettings(
                                            resolution: settingsManager.videoResolution,
                                            frameRate: frameRate,
                                            format: settingsManager.videoFormat
                                        )
                                    }) {
                                        HStack {
                                            Text(frameRate)
                                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                                .foregroundColor(Theme.primaryText)
                                            
                                            Spacer()
                                            
                                            if settingsManager.videoFrameRate == frameRate {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundColor(Theme.accent)
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if frameRate != frameRates.last {
                                        Divider()
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(Theme.cardCornerRadius)
                            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 2)
                            .padding(.horizontal, 20)
                        }
                        
                        // Format
                        VStack(spacing: 0) {
                            Text("Format")
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundColor(Theme.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 12)
                            
                            VStack(spacing: 0) {
                                ForEach(formats, id: \.self) { format in
                                    Button(action: {
                                        settingsManager.saveVideoSettings(
                                            resolution: settingsManager.videoResolution,
                                            frameRate: settingsManager.videoFrameRate,
                                            format: format
                                        )
                                    }) {
                                        HStack {
                                            Text(format)
                                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                                .foregroundColor(Theme.primaryText)
                                            
                                            Spacer()
                                            
                                            if settingsManager.videoFormat == format {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 16, weight: .medium))
                                                    .foregroundColor(Theme.accent)
                                            }
                                        }
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    if format != formats.last {
                                        Divider()
                                            .padding(.leading, 20)
                                    }
                                }
                            }
                            .background(Color.white)
                            .cornerRadius(Theme.cardCornerRadius)
                            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 2)
                            .padding(.horizontal, 20)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Settings Components
struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(Theme.secondaryText)
                .padding(.leading, 4)
            
            VStack(spacing: 0) {
                content
            }
            .background(Color.white)
            .cornerRadius(Theme.cardCornerRadius)
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 2)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let showArrow: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(iconColor)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(Theme.primaryText)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Theme.secondaryText)
                }
                
                Spacer()
                
                if showArrow {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Settings Manager
class SettingsManager: ObservableObject {
    @Published var photoFormat: String = UserDefaults.standard.string(forKey: "photoFormat") ?? "Auto"
    @Published var videoResolution: String = UserDefaults.standard.string(forKey: "videoResolution") ?? "1080p"
    @Published var videoFrameRate: String = UserDefaults.standard.string(forKey: "videoFrameRate") ?? "30fps"
    @Published var videoFormat: String = UserDefaults.standard.string(forKey: "videoFormat") ?? "MOV"
    
    @ObservedObject var localizationManager = LocalizationManager()
    
    var selectedLanguage: String {
        get { localizationManager.currentLanguage }
        set { localizationManager.changeLanguage(to: newValue) }
    }
    
    func savePhotoFormat(_ format: String) {
        photoFormat = format
        UserDefaults.standard.set(format, forKey: "photoFormat")
    }
    
    func saveVideoSettings(resolution: String, frameRate: String, format: String) {
        videoResolution = resolution
        videoFrameRate = frameRate
        videoFormat = format
        UserDefaults.standard.set(resolution, forKey: "videoResolution")
        UserDefaults.standard.set(frameRate, forKey: "videoFrameRate")
        UserDefaults.standard.set(format, forKey: "videoFormat")
    }
    
    func saveLanguage(_ language: String) {
        selectedLanguage = language
        UserDefaults.standard.set(language, forKey: "selectedLanguage")
    }
    
    func clearCache() {
        // Clear image cache
        URLCache.shared.removeAllCachedResponses()
        
        // Clear temporary files
        let tempDirectory = FileManager.default.temporaryDirectory
        do {
            let tempFiles = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in tempFiles {
                try FileManager.default.removeItem(at: file)
            }
        } catch {
            logger.error("Failed to clear cache: \(error.localizedDescription)")
        }
        
        // Clear UserDefaults cache
        UserDefaults.standard.synchronize()
    }
    
    func getCacheSize() -> String {
        // Calculate cache size (simplified)
        return "~2.3 MB"
    }
}

// MARK: - Localization Manager
class LocalizationManager: ObservableObject {
    @Published var currentLanguage: String = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "English"
    
    let availableLanguages = [
        ("English", "en"),
        ("Spanish", "es"),
        ("French", "fr"),
        ("German", "de"),
        ("Italian", "it"),
        ("Portuguese", "pt"),
        ("Chinese", "zh"),
        ("Japanese", "ja"),
        ("Korean", "ko")
    ]
    
    func changeLanguage(to language: String) {
        currentLanguage = language
        UserDefaults.standard.set(language, forKey: "selectedLanguage")
        
        // Post notification for language change
        NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: language)
    }
    
    func localizedString(_ key: String) -> String {
        switch currentLanguage {
        case "Spanish":
            return spanishTranslations[key] ?? key
        case "French":
            return frenchTranslations[key] ?? key
        case "German":
            return germanTranslations[key] ?? key
        case "Italian":
            return italianTranslations[key] ?? key
        case "Portuguese":
            return portugueseTranslations[key] ?? key
        case "Chinese":
            return chineseTranslations[key] ?? key
        case "Japanese":
            return japaneseTranslations[key] ?? key
        case "Korean":
            return koreanTranslations[key] ?? key
        default:
            return englishTranslations[key] ?? key
        }
    }
    
    // Translation dictionaries
    private let englishTranslations: [String: String] = [
        "Select Photo": "Select Photo",
        "Select Video": "Select Video",
        "Settings": "Settings",
        "Photo Settings": "Photo Settings",
        "Video Settings": "Video Settings",
        "Clear Cache": "Clear Cache",
        "Language": "Language",
        "Rate us on App Store": "Rate us on App Store",
        "Invite Friends": "Invite Friends",
        "Send Feedback": "Send Feedback",
        "Privacy & Terms": "Privacy & Terms",
        "Upgrade to BlurYourBub Pro!": "Upgrade to BlurYourBub Pro!",
        "Photo Setting": "Photo Setting",
        "Video Setting": "Video Setting",
        "Automatic format selection": "Automatic format selection",
        "Smaller Size": "Smaller Size",
        "Better Compatibility": "Better Compatibility",
        "Higher Quality": "Higher Quality",
        "Resolution": "Resolution",
        "Frame Rate": "Frame Rate",
        "Format": "Format",
        "This will free up storage space by clearing temporary files and cached data.": "This will free up storage space by clearing temporary files and cached data.",
        "Cancel": "Cancel",
        "Saved!": "Saved!",
        "Image saved to your device.": "Image saved to your device.",
        "OK": "OK",
        "Drawing Error": "Drawing Error",
        "Please draw only within the photo preview area.": "Please draw only within the photo preview area.",
        "New Photo": "New Photo",
        "Apply Blur": "Apply Blur",
        "Share": "Share",
        "Save": "Save",
        "Reset": "Reset",
        "Home": "Home",
        "Language Changed": "Language Changed",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "The app language has been changed to %@. Please close and reopen the app to see the changes.",
        "Restart App": "Restart App",
        "Later": "Later",
        "Close App": "Close App"
    ]
    
    private let spanishTranslations: [String: String] = [
        "Select Photo": "Seleccionar Foto",
        "Select Video": "Seleccionar Video",
        "Settings": "Configuración",
        "Photo Settings": "Configuración de Foto",
        "Video Settings": "Configuración de Video",
        "Clear Cache": "Limpiar Caché",
        "Language": "Idioma",
        "Rate us on App Store": "Califícanos en App Store",
        "Invite Friends": "Invitar Amigos",
        "Send Feedback": "Enviar Comentarios",
        "Privacy & Terms": "Privacidad y Términos",
        "Upgrade to BlurYourBub Pro!": "¡Actualiza a BlurYourBub Pro!",
        "Photo Setting": "Configuración de Foto",
        "Video Setting": "Configuración de Video",
        "Automatic format selection": "Selección automática de formato",
        "Smaller Size": "Tamaño más pequeño",
        "Better Compatibility": "Mejor compatibilidad",
        "Higher Quality": "Mayor calidad",
        "Resolution": "Resolución",
        "Frame Rate": "Velocidad de fotogramas",
        "Format": "Formato",
        "This will free up storage space by clearing temporary files and cached data.": "Esto liberará espacio de almacenamiento eliminando archivos temporales y datos en caché.",
        "Cancel": "Cancelar",
        "Saved!": "¡Guardado!",
        "Image saved to your device.": "Imagen guardada en tu dispositivo.",
        "OK": "OK",
        "Drawing Error": "Error de Dibujo",
        "Please draw only within the photo preview area.": "Por favor dibuja solo dentro del área de vista previa de la foto.",
        "New Photo": "Nueva Foto",
        "Apply Blur": "Aplicar Desenfoque",
        "Share": "Compartir",
        "Save": "Guardar",
        "Reset": "Restablecer",
        "Home": "Inicio",
        "Language Changed": "Idioma Cambiado",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "El idioma de la aplicación ha sido cambiado a %@. Por favor cierra y vuelve a abrir la aplicación para ver los cambios.",
        "Restart App": "Reiniciar App",
        "Later": "Más Tarde",
        "Close App": "Cerrar App"
    ]
    
    private let frenchTranslations: [String: String] = [
        "Select Photo": "Sélectionner Photo",
        "Select Video": "Sélectionner Vidéo",
        "Settings": "Paramètres",
        "Photo Settings": "Paramètres Photo",
        "Video Settings": "Paramètres Vidéo",
        "Clear Cache": "Vider le Cache",
        "Language": "Langue",
        "Rate us on App Store": "Évaluez-nous sur App Store",
        "Invite Friends": "Inviter des Amis",
        "Send Feedback": "Envoyer un Commentaire",
        "Privacy & Terms": "Confidentialité et Conditions",
        "Upgrade to BlurYourBub Pro!": "Passez à BlurYourBub Pro !",
        "Photo Setting": "Paramètre Photo",
        "Video Setting": "Paramètre Vidéo",
        "Automatic format selection": "Sélection automatique du format",
        "Smaller Size": "Taille plus petite",
        "Better Compatibility": "Meilleure compatibilité",
        "Higher Quality": "Qualité supérieure",
        "Resolution": "Résolution",
        "Frame Rate": "Taux de trame",
        "Format": "Format",
        "This will free up storage space by clearing temporary files and cached data.": "Cela libérera de l'espace de stockage en supprimant les fichiers temporaires et les données en cache.",
        "Cancel": "Annuler",
        "Saved!": "Enregistré !",
        "Image saved to your device.": "Image enregistrée sur votre appareil.",
        "OK": "OK",
        "Drawing Error": "Erreur de Dessin",
        "Please draw only within the photo preview area.": "Veuillez dessiner uniquement dans la zone de prévisualisation de la photo.",
        "New Photo": "Nouvelle Photo",
        "Apply Blur": "Appliquer le Flou",
        "Share": "Partager",
        "Save": "Enregistrer",
        "Reset": "Réinitialiser",
        "Home": "Accueil",
        "Language Changed": "Langue Modifiée",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "La langue de l'application a été changée vers %@. Veuillez fermer et rouvrir l'application pour voir les changements.",
        "Restart App": "Redémarrer l'App",
        "Later": "Plus Tard",
        "Close App": "Fermer l'App"
    ]
    
    private let germanTranslations: [String: String] = [
        "Select Photo": "Foto auswählen",
        "Select Video": "Video auswählen",
        "Settings": "Einstellungen",
        "Photo Settings": "Foto-Einstellungen",
        "Video Settings": "Video-Einstellungen",
        "Clear Cache": "Cache leeren",
        "Language": "Sprache",
        "Rate us on App Store": "Bewerten Sie uns im App Store",
        "Invite Friends": "Freunde einladen",
        "Send Feedback": "Feedback senden",
        "Privacy & Terms": "Datenschutz & Bedingungen",
        "Upgrade to BlurYourBub Pro!": "Upgrade auf BlurYourBub Pro!",
        "Photo Setting": "Foto-Einstellung",
        "Video Setting": "Video-Einstellung",
        "Automatic format selection": "Automatische Formatauswahl",
        "Smaller Size": "Kleinere Größe",
        "Better Compatibility": "Bessere Kompatibilität",
        "Higher Quality": "Höhere Qualität",
        "Resolution": "Auflösung",
        "Frame Rate": "Bildrate",
        "Format": "Format",
        "This will free up storage space by clearing temporary files and cached data.": "Dies wird Speicherplatz freigeben, indem temporäre Dateien und zwischengespeicherte Daten gelöscht werden.",
        "Cancel": "Abbrechen",
        "Saved!": "Gespeichert!",
        "Image saved to your device.": "Bild auf Ihrem Gerät gespeichert.",
        "OK": "OK",
        "Drawing Error": "Zeichenfehler",
        "Please draw only within the photo preview area.": "Bitte zeichnen Sie nur innerhalb des Foto-Vorschaubereichs.",
        "New Photo": "Neues Foto",
        "Apply Blur": "Unschärfe anwenden",
        "Share": "Teilen",
        "Save": "Speichern",
        "Reset": "Zurücksetzen",
        "Home": "Startseite",
        "Language Changed": "Sprache Geändert",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "Die App-Sprache wurde zu %@ geändert. Bitte schließen und öffnen Sie die App erneut, um die Änderungen zu sehen.",
        "Restart App": "App Neustarten",
        "Later": "Später",
        "Close App": "App Schließen"
    ]
    
    private let italianTranslations: [String: String] = [
        "Select Photo": "Seleziona Foto",
        "Select Video": "Seleziona Video",
        "Settings": "Impostazioni",
        "Photo Settings": "Impostazioni Foto",
        "Video Settings": "Impostazioni Video",
        "Clear Cache": "Cancella Cache",
        "Language": "Lingua",
        "Rate us on App Store": "Valutaci su App Store",
        "Invite Friends": "Invita Amici",
        "Send Feedback": "Invia Feedback",
        "Privacy & Terms": "Privacy e Termini",
        "Upgrade to BlurYourBub Pro!": "Passa a BlurYourBub Pro!",
        "Photo Setting": "Impostazione Foto",
        "Video Setting": "Impostazione Video",
        "Automatic format selection": "Selezione formato automatica",
        "Smaller Size": "Dimensione più piccola",
        "Better Compatibility": "Migliore compatibilità",
        "Higher Quality": "Qualità superiore",
        "Resolution": "Risoluzione",
        "Frame Rate": "Frame rate",
        "Format": "Formato",
        "This will free up storage space by clearing temporary files and cached data.": "Questo libererà spazio di archiviazione cancellando file temporanei e dati in cache.",
        "Cancel": "Annulla",
        "Saved!": "Salvato!",
        "Image saved to your device.": "Immagine salvata sul tuo dispositivo.",
        "OK": "OK",
        "Drawing Error": "Errore di Disegno",
        "Please draw only within the photo preview area.": "Disegna solo nell'area di anteprima della foto.",
        "New Photo": "Nuova Foto",
        "Apply Blur": "Applica Sfocatura",
        "Share": "Condividi",
        "Save": "Salva",
        "Reset": "Ripristina",
        "Home": "Home",
        "Language Changed": "Lingua Cambiata",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "La lingua dell'app è stata cambiata in %@. Chiudi e riapri l'app per vedere le modifiche.",
        "Restart App": "Riavvia App",
        "Later": "Più Tardi",
        "Close App": "Chiudi App"
    ]
    
    private let portugueseTranslations: [String: String] = [
        "Select Photo": "Selecionar Foto",
        "Select Video": "Selecionar Vídeo",
        "Settings": "Configurações",
        "Photo Settings": "Configurações de Foto",
        "Video Settings": "Configurações de Vídeo",
        "Clear Cache": "Limpar Cache",
        "Language": "Idioma",
        "Rate us on App Store": "Avalie-nos na App Store",
        "Invite Friends": "Convidar Amigos",
        "Send Feedback": "Enviar Feedback",
        "Privacy & Terms": "Privacidade e Termos",
        "Upgrade to BlurYourBub Pro!": "Atualize para BlurYourBub Pro!",
        "Photo Setting": "Configuração de Foto",
        "Video Setting": "Configuração de Vídeo",
        "Automatic format selection": "Seleção automática de formato",
        "Smaller Size": "Tamanho menor",
        "Better Compatibility": "Melhor compatibilidade",
        "Higher Quality": "Qualidade superior",
        "Resolution": "Resolução",
        "Frame Rate": "Taxa de quadros",
        "Format": "Formato",
        "This will free up storage space by clearing temporary files and cached data.": "Isso liberará espaço de armazenamento limpando arquivos temporários e dados em cache.",
        "Cancel": "Cancelar",
        "Saved!": "Salvo!",
        "Image saved to your device.": "Imagem salva no seu dispositivo.",
        "OK": "OK",
        "Drawing Error": "Erro de Desenho",
        "Please draw only within the photo preview area.": "Desenhe apenas na área de visualização da foto.",
        "New Photo": "Nova Foto",
        "Apply Blur": "Aplicar Desfoque",
        "Share": "Compartilhar",
        "Save": "Salvar",
        "Reset": "Redefinir",
        "Home": "Início",
        "Language Changed": "Idioma Alterado",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "O idioma do aplicativo foi alterado para %@. Reinicie o aplicativo para ver as alterações.",
        "Restart App": "Reiniciar App",
        "Later": "Mais Tarde",
        "Close App": "Fechar App"
    ]
    
    private let chineseTranslations: [String: String] = [
        "Select Photo": "选择照片",
        "Select Video": "选择视频",
        "Settings": "设置",
        "Photo Settings": "照片设置",
        "Video Settings": "视频设置",
        "Clear Cache": "清除缓存",
        "Language": "语言",
        "Rate us on App Store": "在App Store评价我们",
        "Invite Friends": "邀请朋友",
        "Send Feedback": "发送反馈",
        "Privacy & Terms": "隐私和条款",
        "Upgrade to BlurYourBub Pro!": "升级到BlurYourBub Pro！",
        "Photo Setting": "照片设置",
        "Video Setting": "视频设置",
        "Automatic format selection": "自动格式选择",
        "Smaller Size": "更小尺寸",
        "Better Compatibility": "更好兼容性",
        "Higher Quality": "更高质量",
        "Resolution": "分辨率",
        "Frame Rate": "帧率",
        "Format": "格式",
        "This will free up storage space by clearing temporary files and cached data.": "这将通过清除临时文件和缓存数据来释放存储空间。",
        "Cancel": "取消",
        "Saved!": "已保存！",
        "Image saved to your device.": "图片已保存到您的设备。",
        "OK": "确定",
        "Drawing Error": "绘制错误",
        "Please draw only within the photo preview area.": "请在照片预览区域内绘制。",
        "New Photo": "新照片",
        "Apply Blur": "应用模糊",
        "Share": "分享",
        "Save": "保存",
        "Reset": "重置",
        "Home": "主页",
        "Language Changed": "语言已更改",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "应用语言已更改为 %@。请关闭并重新打开应用以查看更改。",
        "Restart App": "重启应用",
        "Later": "稍后",
        "Close App": "关闭应用"
    ]
    
    private let japaneseTranslations: [String: String] = [
        "Select Photo": "写真を選択",
        "Select Video": "動画を選択",
        "Settings": "設定",
        "Photo Settings": "写真設定",
        "Video Settings": "動画設定",
        "Clear Cache": "キャッシュをクリア",
        "Language": "言語",
        "Rate us on App Store": "App Storeで評価する",
        "Invite Friends": "友達を招待",
        "Send Feedback": "フィードバックを送信",
        "Privacy & Terms": "プライバシーと利用規約",
        "Upgrade to BlurYourBub Pro!": "BlurYourBub Proにアップグレード！",
        "Photo Setting": "写真設定",
        "Video Setting": "動画設定",
        "Automatic format selection": "自動フォーマット選択",
        "Smaller Size": "小さいサイズ",
        "Better Compatibility": "より良い互換性",
        "Higher Quality": "より高い品質",
        "Resolution": "解像度",
        "Frame Rate": "フレームレート",
        "Format": "フォーマット",
        "This will free up storage space by clearing temporary files and cached data.": "一時ファイルとキャッシュデータをクリアしてストレージ容量を解放します。",
        "Cancel": "キャンセル",
        "Saved!": "保存されました！",
        "Image saved to your device.": "画像がデバイスに保存されました。",
        "OK": "OK",
        "Drawing Error": "描画エラー",
        "Please draw only within the photo preview area.": "写真プレビューエリア内でのみ描画してください。",
        "New Photo": "新しい写真",
        "Apply Blur": "ぼかしを適用",
        "Share": "共有",
        "Save": "保存",
        "Reset": "リセット",
        "Home": "ホーム",
        "Language Changed": "言語が変更されました",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "アプリの言語が %@ に変更されました。変更を確認するにはアプリを閉じて再度開いてください。",
        "Restart App": "アプリを再起動",
        "Later": "後で",
        "Close App": "アプリを閉じる"
    ]
    
    private let koreanTranslations: [String: String] = [
        "Select Photo": "사진 선택",
        "Select Video": "비디오 선택",
        "Settings": "설정",
        "Photo Settings": "사진 설정",
        "Video Settings": "비디오 설정",
        "Clear Cache": "캐시 지우기",
        "Language": "언어",
        "Rate us on App Store": "App Store에서 평가하기",
        "Invite Friends": "친구 초대",
        "Send Feedback": "피드백 보내기",
        "Privacy & Terms": "개인정보 및 이용약관",
        "Upgrade to BlurYourBub Pro!": "BlurYourBub Pro로 업그레이드!",
        "Photo Setting": "사진 설정",
        "Video Setting": "비디오 설정",
        "Automatic format selection": "자동 형식 선택",
        "Smaller Size": "더 작은 크기",
        "Better Compatibility": "더 나은 호환성",
        "Higher Quality": "더 높은 품질",
        "Resolution": "해상도",
        "Frame Rate": "프레임 레이트",
        "Format": "형식",
        "This will free up storage space by clearing temporary files and cached data.": "임시 파일과 캐시된 데이터를 지워서 저장 공간을 확보합니다.",
        "Cancel": "취소",
        "Saved!": "저장됨!",
        "Image saved to your device.": "이미지가 기기에 저장되었습니다.",
        "OK": "확인",
        "Drawing Error": "그리기 오류",
        "Please draw only within the photo preview area.": "사진 미리보기 영역 내에서만 그려주세요.",
        "New Photo": "새 사진",
        "Apply Blur": "블러 적용",
        "Share": "공유",
        "Save": "저장",
        "Reset": "재설정",
        "Home": "홈",
        "Language Changed": "언어가 변경되었습니다",
        "The app language has been changed to %@. Please close and reopen the app to see the changes.": "앱 언어가 %@로 변경되었습니다. 변경사항을 확인하려면 앱을 다시 시작하세요.",
        "Restart App": "앱 재시작",
        "Later": "나중에",
        "Close App": "앱 닫기"
    ]
}

// MARK: - Emoji Picker View
struct EmojiPickerView: View {
    @Environment(\.presentationMode) var presentationMode
    @Binding var selectedEmoji: String
    
    // Popular emojis organized by category with iOS 18 updates
    let emojiCategories: [(String, [String])] = [
        ("Babies & Kids", ["👶", "👶🏻", "👶🏼", "👶🏽", "👶🏾", "👶🏿", "🧒", "🧒🏻", "🧒🏼", "🧒🏽", "🧒🏾", "🧒🏿", "👦", "👦🏻", "👦🏼", "👦🏽", "👦🏾", "👦🏿", "👧", "👧🏻", "👧🏼", "👧🏽", "👧🏾", "👧🏿", "👨‍🍼", "👩‍🍼", "👨‍👩‍👦", "👨‍👩‍👧", "👨‍👩‍👦‍👦", "👨‍👩‍👧‍👧", "👨‍👩‍👧‍👦", "👨‍👦", "👨‍👦‍👦", "👨‍👧", "👨‍👧‍👦", "👨‍👧‍👧", "👩‍👦", "👩‍👦‍👦", "👩‍👧", "👩‍👧‍👦", "👩‍👧‍👧", "👨‍👨‍👦", "👨‍👨‍👧", "👨‍👨‍👦‍👦", "👨‍👨‍👧‍👧", "👨‍👨‍👧‍👦", "👩‍👩‍👦", "👩‍👩‍👧", "👩‍👩‍👦‍👦", "👩‍👩‍👧‍👧", "👩‍👩‍👧‍👦", "👨‍👩‍👦", "👨‍👩‍👧", "👨‍👩‍👦‍👦", "👨‍👩‍👧‍👧", "👨‍👩‍👧‍👦"]),
        ("Faces", ["😀", "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "😊", "😇", "🙂", "🙃", "😉", "😌", "😍", "🥰", "😘", "😗", "😙", "😚", "😋", "😛", "😝", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🤩", "🥳", "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "☹️", "😣", "😖", "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥵", "🥶", "😱", "😨", "😰", "😥", "😓", "🤗", "🤔", "🤭", "🤫", "🤥", "😶", "😐", "😑", "😯", "😦", "😧", "😮", "😲", "🥱", "😴", "🤤", "😪", "😵", "🤐", "🥴", "🤢", "🤮", "🤧", "😷", "🤒", "🤕", "🤑", "🤠", "🥹", "🫠", "🫢", "🫣", "🫡", "🫥", "🫤", "🫦", "🫧", "🫨", "🫶", "🫂", "🫰", "🫱", "🫲", "🫳", "🫴", "🫵", "🫷", "🫸", "🫹", "🫺", "🫻", "🫼", "🫽", "🫾", "🫿"]),
        ("Animals", ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🐤", "🐣", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌", "🐞", "🐜", "🦗", "🕷️", "🕸️", "🦂", "🦟", "🦠", "🐢", "🐍", "🦎", "🦖", "🦕", "🐙", "🦑", "🦐", "🦞", "🦀", "🐡", "🐠", "🐟", "🐬", "🐳", "🐋", "🦈", "🐊", "🐅", "🐆", "🦓", "🦍", "🦧", "🐘", "🦛", "🦏", "🐪", "🐫", "🦒", "🦘", "🐃", "🐂", "🐄", "🐎", "🐖", "🐏", "🐑", "🐐", "🦌", "🐕", "🐩", "🦮", "🐕‍🦺", "🐈", "🐈‍⬛", "🐓", "🦃", "🦚", "🦜", "🦢", "🦩", "🕊️", "🐇", "🦝", "🦨", "🦡", "🦫", "🦦", "🦥", "🐁", "🐀", "🐿️", "🦔"]),
        ("Objects", ["💎", "🔮", "🎈", "🎉", "🎊", "🎋", "🎍", "🎎", "🎏", "🎐", "🎀", "🎁", "🎗️", "🎟️", "🎫", "🎖️", "🏆", "🏅", "🥇", "🥈", "🥉", "⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🪀", "🏓", "🏸", "🏒", "🏑", "🥍", "🏏", "🥅", "⛳", "🪁", "🏹", "🎣", "🤿", "🥊", "🥋", "🎽", "🛹", "🛷️", "⛸️", "🥌", "🎿", "⛷️", "🏂", "🪂", "🏋️‍♀️", "🏋️", "🏋️‍♂️", "🤼‍♀️", "🤼", "🤼‍♂️", "🤸‍♀️", "🤸", "🤸‍♂️", "⛹️‍♀️", "⛹️", "⛹️‍♂️", "🤺", "🤾‍♀️", "🤾", "🤾‍♂️", "🏌️‍♀️", "🏌️", "🏌️‍♂️", "🏇", "🧘‍♀️", "🧘", "🧘‍♂️", "🏄‍♀️", "🏄", "🏄‍♂️", "🏊‍♀️", "🏊", "🏊‍♂️", "🤽‍♀️", "🤽", "🤽‍♂️", "🚣‍♀️", "🚣", "🚣‍♂️", "🧗‍♀️", "🧗", "🧗‍♂️", "🚵‍♀️", "🚵", "🚵‍♂️", "🚴‍♀️", "🚴", "🚴‍♂️", "🏆", "🥇", "🥈", "🥉", "🏅", "🎖️", "🏵️", "🎗️", "🎫", "🎟️", "🎪", "🤹‍♀️", "🤹", "🤹‍♂️", "🎭", "🩰", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🎷", "🎺", "🎸", "🪕", "🎻", "🎲", "♟️", "🎯", "🎳", "🎮", "🎰", "🧩", "🎨", "📱", "📲", "💻", "⌨️", "🖥️", "��️", "🖱️", "🖲️", "💽", "💾", "💿", "📀", "🧮", "🎥", "📷", "📸", "📹", "📼", "🔍", "🔎", "🔏", "🔐", "🔒", "🔓"]),
        ("Symbols", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "☮️", "✝️", "☪️", "🕉️", "☸️", "✡️", "🔯", "🕎", "☯️", "☦️", "🛐", "⛎", "♈", "♉", "♊", "♋", "♌", "♍", "♎", "♏", "♐", "♑", "♒", "♓", "🆔", "⚛️", "🉑", "☢️", "☣️", "📴", "📳", "🈶", "🈚", "🈸", "🈺", "🈷️", "✴️", "🆚", "💮", "🉐", "㊙️", "㊗️", "🈴", "🈵", "🈹", "🈲", "🅰️", "🅱️", "🆎", "🆑", "🅾️", "🆘", "❌", "⭕", "🛑", "⛔", "📛", "🚫", "💯", "💢", "♨️", "🚷", "🚯", "🚳", "🚱", "🔞", "📵", "🚭", "❗", "❕", "❓", "❔", "‼️", "⁉️", "🔅", "🔆", "〽️", "⚠️", "🚸", "🔱", "⚜️", "🔰", "♻️", "✅", "🈯", "💹", "❇️", "✳️", "❎", "🌐", "💠", "Ⓜ️", "🌀", "💤", "🏧", "🚾", "♿", "🅿️", "🛗", "🛂", "🛃", "🛄", "🛅", "🚹", "🚺", "🚼", "🚻", "🚮", "🎦", "📶", "🈁", "🔣", "ℹ️", "🔤", "🔡", "🔠", "🆖", "🆗", "🆙", "🆒", "🆕", "🆓", "0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "🔟", "🔢", "#️⃣", "*️⃣", "⏏️", "▶️", "⏸️", "⏯️", "⏹️", "⏺️", "⏭️", "⏮️", "⏩", "⏪", "⏫", "⏬", "◀️", "🔼", "🔽", "➡️", "⬅️", "⬆️", "⬇️", "↗️", "↘️", "↙️", "↖️", "↕️", "↔️", "↪️", "↩️", "⤴️", "⤵️", "🔀", "🔁", "🔂", "🔄", "🔃", "🎵", "🎶", "➕", "➖", "➗", "✖️", "💲", "💱", "™️", "©️", "®️", "〰️", "➰", "➿", "🔚", "🔙", "🔛", "🔝", "🔜", "✔️", "☑️", "🔘", "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "⚫", "⚪", "🟤", "🔺", "🔻", "🔸", "🔹", "🔶", "🔷", "🔳", "🔲", "▪️", "▫️", "◾", "◽", "◼️", "◻️", "🟥", "🟧", "🟨", "🟩", "🟦", "🟪", "⬛", "⬜", "🟫", "🔈", "🔇", "🔉", "🔊", "🔔", "🔕", "📣", "📢", "👁️‍🗨️", "💬", "💭", "🗯️", "♠️", "♣️", "♥️", "♦️", "🃏", "🎴", "🀄", "🕐", "🕑", "🕒", "🕓", "🕔", "🕕", "🕖", "🕗", "🕘", "🕙", "🕚", "🕛", "🕜", "🕝", "🕞", "🕟", "🕠", "🕡", "🕢", "🕣", "🕤", "🕥", "🕦", "🕧"])
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        Spacer()
                        Text("Choose Emoji")
                            .font(Theme.fontTitle)
                            .foregroundColor(Theme.primaryText)
                        Spacer()
                        // Empty space for balance
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.clear)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    ScrollView {
                        LazyVStack(spacing: 20) {
                            ForEach(emojiCategories, id: \.0) { category in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(category.0)
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .foregroundColor(Theme.primaryText)
                                        .padding(.horizontal, 20)
                                    
                                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                                        ForEach(category.1, id: \.self) { emoji in
                                            Button(action: {
                                                selectedEmoji = emoji
                                                presentationMode.wrappedValue.dismiss()
                                            }) {
                                                Text(emoji)
                                                    .font(.system(size: 32))
                                                    .frame(width: 50, height: 50)
                                                    .background(Color.white)
                                                    .cornerRadius(12)
                                                    .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                        .padding(.top, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }
}

// MARK: - Content Video Picker
struct ContentVideoPicker: UIViewControllerRepresentable {
    let onVideoSelected: (URL) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ContentVideoPicker
        
        init(_ parent: ContentVideoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, error in
                guard let url = url else { return }
                
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: tempURL)
                try? FileManager.default.copyItem(at: url, to: tempURL)
                
                DispatchQueue.main.async {
                    self.parent.onVideoSelected(tempURL)
                }
            }
        }
    }
}
