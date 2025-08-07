import Photos
import Foundation
import SwiftUI
import AVFoundation
import Combine
import os

private let logger = Logger(subsystem: "com.yourapp.blur", category: "video")

class VideoBlurViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedVideoURL: URL?
    @Published var processedVideoURL: URL?
    @Published var isProcessing = false
    @Published var showVideoPicker = false
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    @Published var blurMasks: [BlurMask] = []
    @Published var detectedFaces: [DetectedFace] = []
    
    // Video playback state
    @Published var isPlaying = false
    @Published var currentTime: CMTime = .zero
    @Published var duration: CMTime = .zero
    @Published var videoReady = false
    
    // MARK: - Private Properties
    var player: AVPlayer?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Business Logic Methods
    
    func clearVideo() {
        selectedVideoURL = nil
        processedVideoURL = nil
        blurMasks.removeAll()
        detectedFaces.removeAll()
        isPlaying = false
        currentTime = .zero
        duration = .zero
        videoReady = false
        
        // Remove time observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player = nil
        
        // Reset audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }
    
    func addNewMask() {
        let newMask = BlurMask(
            center: CGPoint(x: 0.5, y: 0.5),
            radius: 50,
            isSelected: true
        )
        blurMasks.append(newMask)
    }
    
    func undoLastMask() {
        if !blurMasks.isEmpty {
            blurMasks.removeLast()
        }
    }
    
    func removeMask(_ mask: BlurMask) {
        blurMasks.removeAll { $0.id == mask.id }
    }
    
    func setupVideoPlayer(url: URL) {
        // Configure audio session for video playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Get video duration
        let asset = AVAsset(url: url)
        Task {
            do {
                let duration = try await asset.load(.duration)
                await MainActor.run {
                    self.duration = duration
                }
            } catch {
                logger.error("Failed to load video duration: \(error.localizedDescription)")
            }
        }
        
        // Setup time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time
        }
        
        // Observe player status
        playerItem.publisher(for: \.status)
            .sink { status in
                if status == .readyToPlay {
                    logger.info("Video loaded successfully")
                    DispatchQueue.main.async {
                        self.videoReady = true
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func togglePlayback() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    func seekToTime(_ time: CMTime) {
        player?.seek(to: time)
        currentTime = time
    }
    
    func exportVideo() {
        guard let processedURL = processedVideoURL else { return }
        
        PHPhotoLibrary.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self?.showAlert = true
                    self?.alertTitle = "Permission Required"
                    self?.alertMessage = "Please allow access to save videos to your photo library."
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: processedURL)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.showAlert = true
                        self?.alertTitle = "Success"
                        self?.alertMessage = "Video saved to your photo library."
                    } else {
                        self?.showAlert = true
                        self?.alertTitle = "Error"
                        self?.alertMessage = error?.localizedDescription ?? "Failed to save video."
                    }
                }
            }
        }
    }
    
    // MARK: - Video Processing
    
    func processVideo() async {
        guard let url = selectedVideoURL else { return }
        
        await MainActor.run {
            isProcessing = true
        }
        
        do {
            let processedURL = try await VideoProcessor.processVideo(
                inputURL: url,
                blurMasks: blurMasks,
                onProgress: { progress in
                    // Update progress if needed
                }
            )
            
            await MainActor.run {
                isProcessing = false
                processedVideoURL = processedURL
            }
        } catch {
            await MainActor.run {
                isProcessing = false
                showAlert = true
                alertTitle = "Processing Error"
                alertMessage = error.localizedDescription
            }
        }
    }
} 
