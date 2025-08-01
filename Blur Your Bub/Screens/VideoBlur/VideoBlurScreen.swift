import SwiftUI
import PhotosUI
import AVKit
import Vision
import CoreImage
import AVFoundation
import Combine
import os

private let logger = Logger(subsystem: "com.yourapp.blur", category: "video")

struct DetectedFace: Identifiable {
    let id = UUID()
    let image: UIImage
    let boundingBox: CGRect
    let time: CMTime
}

struct VideoBlurScreen: View {
    @StateObject private var viewModel = VideoBlurViewModel()

    var body: some View {
        debugPrintState()
        return ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Text("Video Face Blur")
                    .font(.title)
                    .fontWeight(.bold)
                    .padding(.top)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Video Face Blur")
                if viewModel.showFaceGallery {
                    FaceGallerySelectionView(
                        detectedFaces: viewModel.detectedFaces,
                        selectedFaceIDs: $viewModel.selectedFaceIDs,
                        onContinue: {
                            viewModel.showFaceGallery = false
                            viewModel.showBlurStrengthAdjustment = true
                            if let first = viewModel.detectedFaces.first?.image {
                                viewModel.firstFrameImage = first
                            }
                        }
                    )
                } else if viewModel.showBlurStrengthAdjustment, let frameImage = viewModel.firstFrameImage {
                    BlurStrengthAdjustmentView(
                        frameImage: frameImage,
                        detectedFaces: viewModel.detectedFaces,
                        selectedFaceIDs: viewModel.selectedFaceIDs,
                        blurStrength: $viewModel.blurStrength,
                        onBlurVideo: {
                            viewModel.showBlurStrengthAdjustment = false
                            viewModel.processVideoWithSelectedFaces()
                        }
                    )
                } else if let url = viewModel.processedVideoURL ?? viewModel.selectedVideoURL {
                    VideoPlayer(player: AVPlayer(url: url))
                        .frame(height: 280)
                        .cornerRadius(12)
                        .accessibilityLabel("Video preview")
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 280)
                        .overlay(Text("No video selected").foregroundColor(.secondary))
                        .cornerRadius(12)
                        .accessibilityLabel("No video selected")
                }
                Button(action: { viewModel.showVideoPicker = true }) {
                    HStack {
                        Image(systemName: "film")
                        Text("Choose Video")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                .accessibilityLabel("Choose Video")
                .accessibilityHint("Opens the video picker to select a video from your library.")
                if viewModel.isProcessing {
                    ProgressView("Processing...")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.gray)
                        .cornerRadius(12)
                        .accessibilityLabel("Processing video")
                }
                Spacer()
            }
        }
        .onChange(of: viewModel.selectedVideoURL) { newURL in
            if let url = newURL {
                viewModel.scanVideoForFaces(from: url)
            }
        }
        .sheet(isPresented: $viewModel.showVideoPicker) {
            VideoPicker(selectedVideoURL: $viewModel.selectedVideoURL)
        }
        .alert(isPresented: $viewModel.showSaveAlert) {
            Alert(title: Text(viewModel.saveSuccess ? "Success" : "Error"),
                  message: Text(viewModel.saveSuccess ? "Video saved to Photos!" : (viewModel.errorMessage ?? "Unknown error")),
                  dismissButton: .default(Text("OK")))
        }
    }
    
    @discardableResult
    private func debugPrintState() -> Bool {
        print("[DEBUG] VideoBlurScreen.body rendered | showFaceGallery: \(viewModel.showFaceGallery), showBlurStrengthAdjustment: \(viewModel.showBlurStrengthAdjustment), selectedVideoURL: \(String(describing: viewModel.selectedVideoURL)), processedVideoURL: \(String(describing: viewModel.processedVideoURL))")
        return true
    }
}

struct VideoPicker: UIViewControllerRepresentable {
    @Binding var selectedVideoURL: URL?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
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
        init(_ parent: VideoPicker) { self.parent = parent }
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
                    print("[DEBUG] VideoPicker set selectedVideoURL: \(tempURL)")
                }
            }
        }
    }
}

struct FaceGallerySelectionView: View {
    let detectedFaces: [DetectedFace]
    @Binding var selectedFaceIDs: Set<UUID>
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Select Faces to Blur")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Select Faces to Blur")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 16) {
                    ForEach(Array(detectedFaces.enumerated()), id: \ .element.id) { (index, face) in
                        ZStack {
                            Image(uiImage: face.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedFaceIDs.contains(face.id) ? Color.blue : Color.clear, lineWidth: 4)
                                )
                                .onTapGesture {
                                    if selectedFaceIDs.contains(face.id) {
                                        selectedFaceIDs.remove(face.id)
                                    } else {
                                        selectedFaceIDs.insert(face.id)
                                    }
                                }
                                .accessibilityLabel("Face \(index + 1) thumbnail")
                                .accessibilityValue(selectedFaceIDs.contains(face.id) ? "Selected" : "Not selected")
                        }
                    }
                }
                .padding()
            }
            Button(action: onContinue) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(selectedFaceIDs.isEmpty ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(selectedFaceIDs.isEmpty)
            .padding(.horizontal)
            .accessibilityLabel("Continue")
            .accessibilityHint("Proceed to adjust blur strength for selected faces.")
        }
    }
}

struct BlurStrengthAdjustmentView: View {
    let frameImage: UIImage
    let detectedFaces: [DetectedFace]
    let selectedFaceIDs: Set<UUID>
    @Binding var blurStrength: Double
    let onBlurVideo: () -> Void

    var body: some View {
        logger.debug("BlurStrengthAdjustmentView.body rendered")
        return VStack(spacing: 20) {
            Text("Adjust Blur Strength")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("Adjust Blur Strength")
            Image(uiImage: frameImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)
                .clipped()
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Blur Strength: \(Int(blurStrength))")
                Slider(value: $blurStrength, in: 5...40, step: 1)
                    .accentColor(.blue)
                    .padding(.horizontal)
                    .accessibilityLabel("Blur Strength")
                    .accessibilityValue("\(Int(blurStrength))")
            }
            Button(action: {
                print("[DEBUG] Blur Video button tapped")
                onBlurVideo()
            }) {
                Text("Blur Video")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .accessibilityLabel("Blur Video")
            .accessibilityHint("Apply blur to the selected faces in the video.")
        }
    }
}

struct FaceBoundingBox: View {
    let rect: CGRect
    let imageSize: CGSize
    let geoSize: CGSize
    let isSelected: Bool

    var body: some View {
        let scaleX = geoSize.width / imageSize.width
        let scaleY = geoSize.height / imageSize.height
        let box = CGRect(
            x: rect.origin.x * scaleX,
            y: rect.origin.y * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        )
        return Rectangle()
            .stroke(isSelected ? Color.blue : Color.yellow, lineWidth: isSelected ? 4 : 2)
            .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
            .animation(.easeInOut, value: isSelected)
    }
} 

class SelectedFaceBlurVideoCompositor: NSObject, AVVideoCompositing {
    static var selectedFaceRects: [CGRect] = [] // In image coordinates of first frame
    static var blurStrength: Double = 15
    var sourcePixelBufferAttributes: [String : Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferOpenGLESCompatibilityKey as String: true
    ]
    var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferOpenGLESCompatibilityKey as String: true
    ]
    private let processingQueue = DispatchQueue(label: "video.compositor.queue")
    private let ciContext = CIContext()
    private var faceDetector: CIDetector?
    override init() {
        super.init()
        setupFaceDetector()
    }
    private func setupFaceDetector() {
        faceDetector = CIDetector(
            ofType: CIDetectorTypeFace,
            context: ciContext,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )
    }
    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}
    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        processingQueue.async {
            self.processRequest(asyncVideoCompositionRequest)
        }
    }
    private func processRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let trackIDNumber = request.sourceTrackIDs[0] as? NSNumber else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 1, userInfo: nil))
            return
        }
        let trackID = CMPersistentTrackID(truncating: trackIDNumber)
        guard let sourcePixelBuffer = request.sourceFrame(byTrackID: trackID) else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 1, userInfo: nil))
            return
        }
        let ciImage = CIImage(cvPixelBuffer: sourcePixelBuffer)
        let processedImage = applySelectedFaceBlur(to: ciImage)
        guard let outputPixelBuffer = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "VideoCompositor", code: 2, userInfo: nil))
            return
        }
        ciContext.render(processedImage, to: outputPixelBuffer)
        request.finish(withComposedVideoFrame: outputPixelBuffer)
    }
    private func applySelectedFaceBlur(to image: CIImage) -> CIImage {
        guard let detector = faceDetector else { return image }
        let faces = detector.features(in: image) as? [CIFaceFeature] ?? []
        print("[DEBUG] Detected \(faces.count) faces in frame")
        print("[DEBUG] Selected face rects: \(SelectedFaceBlurVideoCompositor.selectedFaceRects)")
        var outputImage = image
        var blurApplied = false
        // For each detected face, check if it matches a selected face (by overlap)
        for face in faces {
            print("[DEBUG] Detected face bounds: \(face.bounds)")
            let shouldBlur = SelectedFaceBlurVideoCompositor.selectedFaceRects.contains { selected in
                // Simple overlap check
                selected.intersects(face.bounds)
            }
            if shouldBlur {
                print("[DEBUG] Applying blur to face at \(face.bounds)")
                let blurArea = face.bounds.insetBy(dx: -10, dy: -10)
                let blurFilter = CIFilter(name: "CIGaussianBlur")!
                blurFilter.setValue(image.cropped(to: blurArea), forKey: kCIInputImageKey)
                blurFilter.setValue(SelectedFaceBlurVideoCompositor.blurStrength, forKey: kCIInputRadiusKey)
                guard let blurredRegion = blurFilter.outputImage else { continue }
                let composite = CIFilter(name: "CISourceOverCompositing")!
                composite.setValue(blurredRegion, forKey: kCIInputImageKey)
                composite.setValue(outputImage, forKey: kCIInputBackgroundImageKey)
                if let result = composite.outputImage {
                    outputImage = result
                    blurApplied = true
                }
            }
        }
        // If no faces detected or no blur applied, blur the center of the frame for debugging
        if faces.isEmpty || !blurApplied {
            print("[DEBUG] No faces blurred, applying debug blur to center")
            let width = image.extent.width
            let height = image.extent.height
            let centerRect = CGRect(x: width/2 - 50, y: height/2 - 50, width: 100, height: 100)
            let blurFilter = CIFilter(name: "CIGaussianBlur")!
            blurFilter.setValue(image.cropped(to: centerRect), forKey: kCIInputImageKey)
            blurFilter.setValue(SelectedFaceBlurVideoCompositor.blurStrength, forKey: kCIInputRadiusKey)
            if let blurredRegion = blurFilter.outputImage {
                let composite = CIFilter(name: "CISourceOverCompositing")!
                composite.setValue(blurredRegion, forKey: kCIInputImageKey)
                composite.setValue(outputImage, forKey: kCIInputBackgroundImageKey)
                if let result = composite.outputImage {
                    outputImage = result
                }
            }
        }
        return outputImage
    }
} 