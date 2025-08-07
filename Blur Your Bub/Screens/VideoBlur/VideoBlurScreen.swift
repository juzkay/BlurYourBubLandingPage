import SwiftUI
import PhotosUI
import AVKit
import Vision
import CoreImage
import AVFoundation
import Combine
import os

private let logger = Logger(subsystem: "com.yourapp.blur", category: "video")

// MARK: - Data Models

struct BlurMask: Identifiable, Equatable {
    let id = UUID()
    var center: CGPoint
    var radius: CGFloat
    var isSelected: Bool = false
    var faceTrackingEnabled: Bool = true
    
    static func == (lhs: BlurMask, rhs: BlurMask) -> Bool {
        lhs.id == rhs.id
    }
}

struct DetectedFace: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let confidence: Float
}

// MARK: - Main Video Blur Screen

struct VideoBlurScreen: View {
    @StateObject private var viewModel = VideoBlurViewModel()
    @Environment(\.dismiss) private var dismiss
    let selectedVideoURL: URL?
    
    // Export modal state
    @State private var showExportSheet = false
    @State private var showShareSheet = false
    @State private var showSaveSuccess = false
    
    init(selectedVideoURL: URL? = nil) {
        self.selectedVideoURL = selectedVideoURL
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header - Clean UI like photo blur screen
                HStack(alignment: .center, spacing: 0) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "house")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(Theme.accent)
                            .padding(.leading, 8)
                            .padding(.top, 8)
                    }
                    .contentShape(Rectangle())
                    
                    Spacer()
                    
                    Button(action: { 
                        // Reset and open new video picker
                        viewModel.clearVideo()
                        viewModel.showVideoPicker = true
                    }) {
                        Image(systemName: "video.badge.plus")
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
                    
                    Button(action: { /* TODO: Add settings */ }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .background(Theme.card)
                            .cornerRadius(Theme.buttonCornerRadius)
                            .padding(.trailing, 8)
                            .padding(.top, 8)
                    }
                    .contentShape(Rectangle())
                }
                .zIndex(10)
                
                // Video Player Area (larger like photo feature)
                if let url = selectedVideoURL ?? viewModel.selectedVideoURL {
                    VideoPlayerView(
                        url: url,
                        blurMasks: $viewModel.blurMasks,
                        detectedFaces: $viewModel.detectedFaces,
                        isProcessing: $viewModel.isProcessing,
                        onVideoProcessed: { processedURL in
                            viewModel.processedVideoURL = processedURL
                        },
                        viewModel: viewModel
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.45) // Reduced to match video preview
                    .cornerRadius(Theme.cardCornerRadius)
                    .shadow(color: Theme.shadow, radius: 8, x: 0, y: 2)
                    .padding(.horizontal, 20)
                    .padding(.top, 16) // Reduced from 20 to 16
                    .onAppear {
                        viewModel.setupVideoPlayer(url: url)
                    }
                    
                    // Video Controls (OFF the video)
                    VideoControlsView(
                        isPlaying: $viewModel.isPlaying,
                        currentTime: $viewModel.currentTime,
                        duration: $viewModel.duration,
                        onPlayPause: { viewModel.togglePlayback() },
                        onSeek: { time in viewModel.seekToTime(time) }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12) // Reduced from 16 to 12
                    
                    // Blur Masks List
                    if !viewModel.blurMasks.isEmpty {
                        BlurMasksListView(
                            blurMasks: $viewModel.blurMasks,
                            onDeleteMask: { mask in
                                viewModel.removeMask(mask)
                            }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 12) // Reduced from 16 to 12
                    }
                    
                    Spacer()
                    
                } else {
                    // Empty State
                    VStack(spacing: 24) {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 64))
                                .foregroundColor(Theme.accent)
                            
                            Text("Select a video to get started")
                                .font(Theme.fontSubtitle)
                                .foregroundColor(Theme.primaryText)
                                .multilineTextAlignment(.center)
                            
                            Text("Tap faces to blur them automatically throughout the video")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: UIScreen.main.bounds.height * 0.45) // Reduced to match video preview
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(Theme.cardCornerRadius)
                    .padding(.horizontal, 20)
                    .padding(.top, 40)
                    
                    Spacer()
                }
                
                // Bottom Button Bar (like photo feature)
                VStack(spacing: 0) {
                    // Action Buttons Row
                    HStack(spacing: 12) {
                        // + BLUR Button
                        Button(action: { viewModel.addNewMask() }) {
                            Text("ADD BLUR")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Theme.accent)
                                .foregroundColor(.white)
                                .cornerRadius(Theme.buttonCornerRadius)
                        }
                        
                        // Undo Button
                        Button(action: { viewModel.undoLastMask() }) {
                            Text("UNDO")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Color.clear)
                                .foregroundColor(.black)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.buttonCornerRadius)
                                        .stroke(Color.black, lineWidth: 2)
                                )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    
                    // Done Button
                    Button(action: { 
                        showExportSheet = true
                    }) {
                        HStack {
                            Text("DONE")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Theme.accent)
                        .foregroundColor(.white)
                        .cornerRadius(Theme.buttonCornerRadius)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            
            // Export modal overlay
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
                                Task {
                                    await viewModel.processVideo()
                                    if let processedURL = viewModel.processedVideoURL {
                                        // Save video to camera roll
                                        PHPhotoLibrary.shared().performChanges({
                                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: processedURL)
                                        }) { success, error in
                                            DispatchQueue.main.async {
                                                if success {
                                                    showSaveSuccess = true
                                                }
                                                showExportSheet = false
                                            }
                                        }
                                    }
                                }
                            },
                            onShare: {
                                Task {
                                    await viewModel.processVideo()
                                    showExportSheet = false
                                    showShareSheet = true
                                }
                            },
                            onCancel: { showExportSheet = false },
                            title: "Export Video",
                            saveButtonText: "Save Video to Device"
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
        .navigationBarHidden(true)
        .onAppear {
            if let url = selectedVideoURL {
                viewModel.selectedVideoURL = url
                viewModel.setupVideoPlayer(url: url)
            }
        }
        .sheet(isPresented: $viewModel.showVideoPicker) {
            VideoPicker(selectedVideoURL: $viewModel.selectedVideoURL)
        }
        .sheet(isPresented: $showShareSheet) {
            if let processedURL = viewModel.processedVideoURL {
                ShareSheet(activityItems: [processedURL])
            } else {
                Text("No video available")
            }
        }
        .alert(isPresented: $viewModel.showAlert) {
            Alert(
                title: Text(viewModel.alertTitle),
                message: Text(viewModel.alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $showSaveSuccess) {
            Alert(
                title: Text("Saved!"),
                message: Text("Video saved to your device."),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

// MARK: - Video Player View

struct VideoPlayerView: View {
    let url: URL
    @Binding var blurMasks: [BlurMask]
    @Binding var detectedFaces: [DetectedFace]
    @Binding var isProcessing: Bool
    let onVideoProcessed: (URL) -> Void
    
    @ObservedObject var viewModel: VideoBlurViewModel
    @State private var videoSize: CGSize = CGSize(width: 300, height: 300)
    @State private var isRealTimeBlurEnabled = true
    
    var body: some View {
        ZStack {
            // Video Player (without controls)
            VideoPlayer(player: viewModel.player)
                .disabled(true) // Disable built-in controls
                .onAppear {
                    loadVideo(url: url)
                }
            
            // Real-time Blur Overlay
            if isRealTimeBlurEnabled && !blurMasks.isEmpty {
                RealTimeBlurOverlay(
                    blurMasks: blurMasks,
                    detectedFaces: detectedFaces,
                    videoSize: videoSize
                )
            }
            
            // Face Detection Overlay (for selection)
            FaceDetectionOverlay(
                blurMasks: $blurMasks,
                detectedFaces: $detectedFaces,
                videoSize: videoSize
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
            // Handle video end
        }
    }
    
    private func loadVideo(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        viewModel.player?.replaceCurrentItem(with: playerItem)
        
        // Get video size
        let asset = AVAsset(url: url)
        if let videoTrack = asset.tracks(withMediaType: .video).first {
            videoSize = videoTrack.naturalSize
        }
    }
}

// MARK: - Video Controls View

struct VideoControlsView: View {
    @Binding var isPlaying: Bool
    @Binding var currentTime: CMTime
    @Binding var duration: CMTime
    let onPlayPause: () -> Void
    let onSeek: (CMTime) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Play/Pause Button
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(Theme.accent)
            }
            
            // Timeline Slider
            if duration.seconds > 0 {
                VStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { currentTime.seconds },
                            set: { newValue in
                                let newTime = CMTime(seconds: newValue, preferredTimescale: 600)
                                onSeek(newTime)
                            }
                        ),
                        in: 0...duration.seconds
                    )
                    .accentColor(Theme.accent)
                    
                    HStack {
                        Text(formatTime(currentTime))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                        
                        Spacer()
                        
                        Text(formatTime(duration))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.white)
        .cornerRadius(Theme.buttonCornerRadius)
        .shadow(color: Theme.shadow, radius: 4, x: 0, y: 2)
    }
    
    private func formatTime(_ time: CMTime) -> String {
        let seconds = Int(time.seconds)
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

// MARK: - Blur Masks List View

struct BlurMasksListView: View {
    @Binding var blurMasks: [BlurMask]
    let onDeleteMask: (BlurMask) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blur Masks")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Theme.primaryText)
            
            ForEach(blurMasks) { mask in
                HStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 12, height: 12)
                    
                    Text("Mask \(blurMasks.firstIndex(of: mask)?.advanced(by: 1) ?? 0)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.primaryText)
                    
                    Spacer()
                    
                    Button(action: { onDeleteMask(mask) }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white)
                .cornerRadius(Theme.buttonCornerRadius)
                .shadow(color: Theme.shadow, radius: 2, x: 0, y: 1)
            }
        }
    }
}

// MARK: - Real-time Blur Overlay

struct RealTimeBlurOverlay: View {
    let blurMasks: [BlurMask]
    let detectedFaces: [DetectedFace]
    let videoSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Apply blur masks in real-time
                ForEach(blurMasks) { mask in
                    BlurCircleView(
                        mask: mask,
                        videoSize: videoSize,
                        overlaySize: geometry.size
                    )
                }
            }
        }
    }
}

// MARK: - Blur Circle View

struct BlurCircleView: View {
    let mask: BlurMask
    let videoSize: CGSize
    let overlaySize: CGSize
    
    var body: some View {
        let scaleX = overlaySize.width / videoSize.width
        let scaleY = overlaySize.height / videoSize.height
        
        let centerX = mask.center.x * scaleX
        let centerY = mask.center.y * scaleY
        let radius = mask.radius * min(scaleX, scaleY)
        
        // Create a blurred circle effect
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.black.opacity(0.9),
                        Color.black.opacity(0.7),
                        Color.black.opacity(0.5),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            .frame(width: radius * 2, height: radius * 2)
            .position(x: centerX, y: centerY)
            .blur(radius: 15) // Additional blur effect
            .overlay(
                // Add a subtle border to make it more visible
                Circle()
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: centerX, y: centerY)
            )
    }
}

// MARK: - Face Detection Overlay

struct FaceDetectionOverlay: View {
    @Binding var blurMasks: [BlurMask]
    @Binding var detectedFaces: [DetectedFace]
    let videoSize: CGSize
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Detected faces (yellow rectangles)
                ForEach(detectedFaces) { face in
                    FaceBoundingBox(
                        rect: face.boundingBox,
                        videoSize: videoSize,
                        overlaySize: geometry.size,
                        isSelected: false
                    )
                    .onTapGesture {
                        addBlurMask(at: face.boundingBox, in: geometry.size)
                    }
                }
                
                // Blur masks (blue circles)
                ForEach($blurMasks) { $mask in
                    BlurMaskView(
                        mask: $mask,
                        videoSize: videoSize,
                        overlaySize: geometry.size
                    )
                }
            }
        }
    }
    
    private func addBlurMask(at faceRect: CGRect, in overlaySize: CGSize) {
        let scaleX = overlaySize.width / videoSize.width
        let scaleY = overlaySize.height / videoSize.height
        
        let centerX = (faceRect.midX * scaleX)
        let centerY = (faceRect.midY * scaleY)
        let radius = min(faceRect.width, faceRect.height) * min(scaleX, scaleY) / 2
        
        let newMask = BlurMask(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius
        )
        
        blurMasks.append(newMask)
    }
}

// MARK: - Face Bounding Box

struct FaceBoundingBox: View {
    let rect: CGRect
    let videoSize: CGSize
    let overlaySize: CGSize
    let isSelected: Bool

    var body: some View {
        let scaleX = overlaySize.width / videoSize.width
        let scaleY = overlaySize.height / videoSize.height
        
        let scaledRect = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        
        Rectangle()
            .stroke(isSelected ? Theme.accent : Color.yellow, lineWidth: 2)
            .background(isSelected ? Theme.accent.opacity(0.2) : Color.clear)
            .frame(width: scaledRect.width, height: scaledRect.height)
            .position(x: scaledRect.midX, y: scaledRect.midY)
    }
}

// MARK: - Blur Mask View

struct BlurMaskView: View {
    @Binding var mask: BlurMask
    let videoSize: CGSize
    let overlaySize: CGSize
    
    @State private var isDragging = false
    @State private var isResizing = false
    
    var body: some View {
        ZStack {
            // Main circle
            Circle()
                .stroke(Theme.accent, lineWidth: 3)
                .background(Theme.accent.opacity(0.2))
                .frame(width: mask.radius * 2, height: mask.radius * 2)
                .position(mask.center)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isResizing {
                                isDragging = true
                                mask.center = value.location
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                        }
                )
            
            // Resize handle
            Circle()
                .fill(Theme.accent)
                .frame(width: 20, height: 20)
                .position(
                    x: mask.center.x + mask.radius,
                    y: mask.center.y
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isResizing = true
                            let distance = sqrt(
                                pow(value.location.x - mask.center.x, 2) +
                                pow(value.location.y - mask.center.y, 2)
                            )
                            mask.radius = max(20, min(distance, 200)) // Min 20, max 200
                        }
                        .onEnded { _ in
                            isResizing = false
                        }
                )
        }
    }
}

// MARK: - Video Picker

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    
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
        let parent: VideoPicker
        
        init(_ parent: VideoPicker) {
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
                    self.parent.selectedVideoURL = tempURL
                }
            }
        }
    }
}

// MARK: - Extensions

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
} 