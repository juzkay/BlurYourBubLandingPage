import Foundation
import AVFoundation

class VideoBlurProcessor {
    static func processExistingVideo(inputURL: URL, outputURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        let asset = AVAsset(url: inputURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(false, NSError(domain: "VideoProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"]))
            return
        }
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        // Add video track
        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            completion(false, NSError(domain: "VideoProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create composition track"]))
            return
        }
        do {
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
        } catch {
            completion(false, error)
            return
        }
        // Set up video composition
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.renderSize = videoTrack.naturalSize
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(videoTrack.preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        // Apply face blur filter
        videoComposition.customVideoCompositorClass = FaceBlurVideoCompositor.self
        // Export
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(false, NSError(domain: "VideoProcessing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create export session"]))
            return
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        exportSession.videoComposition = videoComposition
        exportSession.exportAsynchronously {
            DispatchQueue.main.async {
                switch exportSession.status {
                case .completed:
                    completion(true, nil)
                case .failed:
                    completion(false, exportSession.error)
                default:
                    completion(false, NSError(domain: "VideoProcessing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Export cancelled or unknown error"]))
                }
            }
        }
    }
} 