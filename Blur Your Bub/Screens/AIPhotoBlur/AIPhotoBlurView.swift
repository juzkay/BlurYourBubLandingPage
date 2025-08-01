import SwiftUI
import PhotosUI

// MARK: - Face Gallery Components
struct FaceGalleryView: View {
    @Binding var detectedFaces: [PhotoDetectedFace]
    let onSelectionChanged: () -> Void
    
    private let faceSize: CGFloat = 80
    private let spacing: CGFloat = 12
    
    var selectedCount: Int {
        detectedFaces.filter { $0.isSelected }.count
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Header with selection count
            HStack {
                Text("Select faces to blur")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Selected: \(selectedCount)/\(detectedFaces.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            
            // Face gallery
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(Array(detectedFaces.enumerated()), id: \.element.id) { index, face in
                        FaceThumbnailView(
                            face: face,
                            index: index + 1,
                            size: faceSize
                        ) {
                            toggleFaceSelection(face.id)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: faceSize + 32) // Extra space for selection indicator
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private func toggleFaceSelection(_ faceId: UUID) {
        if let index = detectedFaces.firstIndex(where: { $0.id == faceId }) {
            detectedFaces[index].isSelected.toggle()
            onSelectionChanged()
        }
    }
}

struct FaceThumbnailView: View {
    let face: PhotoDetectedFace
    let index: Int
    let size: CGFloat
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                // Face image
                if let faceImage = face.faceImage {
                    Image(uiImage: faceImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(face.isSelected ? Color.green : Color.gray.opacity(0.3), lineWidth: 3)
                        )
                } else {
                    // Fallback if no face image
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: size, height: size)
                        .overlay(
                            Image(systemName: "person.crop.circle")
                                .font(.title)
                                .foregroundColor(.gray)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(face.isSelected ? Color.green : Color.gray.opacity(0.3), lineWidth: 3)
                        )
                }
                
                // Selection indicator
                if face.isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.green)
                                .background(Color.white)
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            
            // Face number label
            Text("Face \(index)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .onTapGesture {
            onTap()
        }
    }
}

struct AIPhotoBlurView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImage: UIImage?
    @State private var detectedFaces: [PhotoDetectedFace] = []
    @State private var processedImage: UIImage?
    @State private var showingImagePicker = true
    @State private var showingShareSheet = false
    @State private var showExportSheet = false
    @State private var showSaveSuccess = false
    @State private var isProcessingFaces = false
    @State private var faceDetector = PhotoFaceDetector()
    @State private var showNoFacesAlert = false
    @State private var isPreviewMode = false // Hide face rectangles during preview
    
    var hasSelectedFaces: Bool {
        detectedFaces.contains { $0.isSelected }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Theme.background.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Header
                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(Theme.accent)
                        
                        Spacer()
                        
                        Text("AI Photo Blur")
                            .font(Theme.fontSubtitle)
                            .foregroundColor(Theme.primaryText)
                        
                        Spacer()
                        
                        if selectedImage != nil && !detectedFaces.isEmpty {
                            Button("New Photo") {
                                resetForNewPhoto()
                                showingImagePicker = true
                            }
                            .foregroundColor(Theme.accent)
                        } else {
                            Color.clear.frame(width: 80) // Spacer for alignment
                        }
                    }
                    .padding(.horizontal)
                    
                    if let image = processedImage ?? selectedImage {
                        // Photo display (no overlay needed)
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(12)
                            .padding(.horizontal)
                        
                        // Face Gallery for selection
                        if !detectedFaces.isEmpty && !isPreviewMode {
                            FaceGalleryView(
                                detectedFaces: $detectedFaces,
                                onSelectionChanged: {
                                    // Apply real-time preview when selection changes
                                    if hasSelectedFaces {
                                        applyRealtimePreview()
                                    } else {
                                        processedImage = nil
                                    }
                                }
                            )
                            .padding(.horizontal)
                        } else if !detectedFaces.isEmpty && isPreviewMode {
                            VStack(spacing: 4) {
                                Text("Preview Mode")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Theme.primaryText)
                                
                                Text("Face selection hidden during preview")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(Theme.secondaryText)
                            }
                            .padding(.horizontal)
                        } else if isProcessingFaces {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Detecting faces...")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                        } else if isPreviewMode {
                            Text("Preview Mode • Face selection hidden")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.secondaryText)
                                .padding(.horizontal)
                        }
                        
                        Spacer()
                        
                        // Action buttons
                        VStack(spacing: 12) {
                            if hasSelectedFaces {
                                // Preview and Apply buttons row
                                HStack(spacing: 12) {
                                    // Preview Button
                                    Button(action: {
                                        togglePreviewMode()
                                    }) {
                                        Text(isPreviewMode ? "Show Selection" : "Preview Blur")
                                            .font(.system(size: 16, weight: .semibold))
                                            .padding(16)
                                            .frame(maxWidth: .infinity)
                                            .background(isPreviewMode ? Color.orange.opacity(0.8) : Theme.accent.opacity(0.8))
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    }
                                    
                                    // Apply Blur Button
                                    Button("Apply Blur") {
                                        finalizeBlur()
                                    }
                                    .font(.system(size: 16, weight: .bold))
                                    .padding(16)
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.accent)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                            }
                            
                            // Export button (after final blur is applied)
                            if processedImage != nil && !isPreviewMode {
                                Button("Export") {
                                    showExportSheet = true
                                }
                                .font(.system(size: 18, weight: .semibold))
                                .padding(16)
                                .frame(maxWidth: .infinity)
                                .background(Color.green.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        
                    } else {
                        // Empty state
                        VStack(spacing: 20) {
                            Spacer()
                            
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 60))
                                .foregroundColor(Theme.accent.opacity(0.6))
                            
                            VStack(spacing: 8) {
                                Text("AI Face Detection")
                                    .font(Theme.fontTitle)
                                    .foregroundColor(Theme.primaryText)
                                
                                Text("Select a photo to automatically detect and blur faces")
                                    .font(Theme.fontBody)
                                    .foregroundColor(Theme.secondaryText)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            
                            Button("Choose Photo") {
                                showingImagePicker = true
                            }
                            .font(Theme.fontSubtitle)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 16)
                            .background(Theme.accent)
                            .foregroundColor(.white)
                            .cornerRadius(Theme.buttonCornerRadius)
                            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
                            
                            Spacer()
                        }
                    }
                }
                
                // Export modal
                if showExportSheet {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(1)
                    
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
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showingShareSheet = true
                                }
                            },
                            onCancel: { showExportSheet = false }
                        )
                        .frame(maxWidth: 340)
                        Spacer()
                    }
                    .zIndex(2)
                    .transition(.scale)
                }
            }
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                selectedImage: $selectedImage,
                onImageSelected: {
                    if let image = selectedImage {
                        detectFacesInImage(image)
                    }
                }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let image = processedImage {
                ShareSheet(activityItems: [image])
            }
        }
        .alert(isPresented: $showSaveSuccess) {
            Alert(title: Text("Saved!"), message: Text("Image saved to your device."), dismissButton: .default(Text("OK")))
        }
        .alert("No Faces Detected", isPresented: $showNoFacesAlert) {
            Button("Try Manual Mode") {
                switchToManualMode()
            }
            Button("Choose Different Photo") {
                resetForNewPhoto()
                showingImagePicker = true
            }
            Button("Cancel", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("We couldn't detect any faces in this photo. You can try manual mode to draw blur areas yourself, or choose a different photo.")
        }
    }
    
    // MARK: - Functions
    
    private func detectFacesInImage(_ image: UIImage) {
        isProcessingFaces = true
        detectedFaces = []
        processedImage = nil
        
        print("[AIPhotoBlurView] Starting face detection for image size: \(image.size)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            print("[AIPhotoBlurView] Starting enhanced multi-strategy face detection...")
            
            // PRIMARY: Use professional AI detection (Core ML + Landmarks)
            print("[AIPhotoBlurView] 🏭 PROFESSIONAL AI: Starting industry-standard AI detection...")
            let professionalFaces = self.faceDetector.detectFacesWithProfessionalAI(in: image)
            
            var faces = professionalFaces
            
            // FALLBACK: If professional AI finds no faces, try multi-strategy
            if faces.isEmpty {
                print("[AIPhotoBlurView] 🏭 EMERGENCY FALLBACK: Professional AI found 0 faces, trying multi-strategy...")
                faces = self.faceDetector.detectFacesMultiStrategy(in: image)
            }
            
            print("[AIPhotoBlurView] Multi-strategy detection complete: \(faces.count) faces found")
            
            // If still no faces found, try individual strategies as fallback
            var finalFaces = faces
            if faces.isEmpty {
                print("[AIPhotoBlurView] No faces found with multi-strategy, trying individual fallbacks...")
                
                // Try landmarks detection
                let landmarksFaces = self.faceDetector.detectFacesWithLandmarks(in: image)
                if !landmarksFaces.isEmpty {
                    finalFaces = landmarksFaces
                    print("[AIPhotoBlurView] Fallback landmarks found: \(landmarksFaces.count) faces")
                    print("🔍 [AIPhotoBlurView] ===== FALLBACK FACES DETAILS =====")
                    for (index, face) in landmarksFaces.enumerated() {
                        print("🔍 [AIPhotoBlurView] Fallback face \(index + 1): \(face.boundingBox)")
                        print("🔍 [AIPhotoBlurView]   Dimensions: \(face.boundingBox.width) x \(face.boundingBox.height)")
                        print("🔍 [AIPhotoBlurView]   Aspect ratio: \(face.boundingBox.width / face.boundingBox.height)")
                        print("🔍 [AIPhotoBlurView]   Center: (\(face.boundingBox.midX), \(face.boundingBox.midY))")
                        print("🔍 [AIPhotoBlurView]   Area: \(face.boundingBox.width * face.boundingBox.height) pixels")
                    }
                    print("🔍 [AIPhotoBlurView] ===== END FALLBACK DETAILS =====")
                } else {
                    // Try aggressive detection
                    let aggressiveFaces = self.faceDetector.detectFacesAggressive(in: image)
                    if !aggressiveFaces.isEmpty {
                        finalFaces = aggressiveFaces
                        print("[AIPhotoBlurView] Fallback aggressive found: \(aggressiveFaces.count) faces")
                    }
                }
            }
            
            print("[AIPhotoBlurView] Final detection result: \(finalFaces.count) faces found")
            
            DispatchQueue.main.async {
                self.detectedFaces = finalFaces
                self.isProcessingFaces = false
                
                // Show fallback message if no faces detected
                if finalFaces.isEmpty {
                    print("[AIPhotoBlurView] No faces detected, showing alert")
                    self.showNoFacesAlert = true
                } else {
                    print("[AIPhotoBlurView] Successfully detected \(finalFaces.count) faces")
                }
            }
        }
    }
    

    
    private func applyRealtimePreview() {
        guard let originalImage = selectedImage else { return }
        
        let selectedFaceRects = detectedFaces
            .filter { $0.isSelected }
            .map { $0.boundingBox }
        
        // Use existing blur processor with face rectangles
        processedImage = BlurProcessor.applyBlurToFaces(
            to: originalImage,
            faceRects: selectedFaceRects,
            blurRadius: 50.0 // Moderate blur for preview
        )
    }
    
    private func togglePreviewMode() {
        isPreviewMode.toggle()
        
        if isPreviewMode {
            // Entering preview mode - apply temporary blur
            applyRealtimePreview()
        } else {
            // Exiting preview mode - reset to original with face rectangles
            if !hasSelectedFaces {
                processedImage = nil
            } else {
                // Keep the preview blur but show rectangles again
                applyRealtimePreview()
            }
        }
    }
    
    private func finalizeBlur() {
        guard let originalImage = selectedImage else { return }
        
        let selectedFaceRects = detectedFaces
            .filter { $0.isSelected }
            .map { $0.boundingBox }
        
        // Apply final high-quality blur
        processedImage = BlurProcessor.applyBlurToFaces(
            to: originalImage,
            faceRects: selectedFaceRects,
            blurRadius: 70.0 // Final blur strength
        )
        
        // Exit preview mode after finalizing
        isPreviewMode = false
    }
    
    private func resetForNewPhoto() {
        selectedImage = nil
        detectedFaces = []
        processedImage = nil
        isProcessingFaces = false
        isPreviewMode = false
    }
    
    private func switchToManualMode() {
        // Close this view and return the selected image for manual editing
        // We'll need to communicate with the parent ContentView for this
        dismiss()
        
        // Note: In a production app, you might want to use a coordinator pattern
        // or pass a callback to handle this transition more elegantly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // This is a simple approach - in real implementation you might want
            // to use a more sophisticated navigation pattern
            NotificationCenter.default.post(
                name: NSNotification.Name("SwitchToManualPhotoEdit"),
                object: selectedImage
            )
        }
    }
}

// MARK: - Preview
#Preview {
    AIPhotoBlurView()
}