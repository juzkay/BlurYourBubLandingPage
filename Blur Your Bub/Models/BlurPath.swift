import CoreGraphics
import Foundation

struct BlurPath {
    var points: [CGPoint]
}

// MARK: - Emoji Sticker Model
struct EmojiSticker: Identifiable {
    let id = UUID()
    var emoji: String
    var position: CGPoint
    var size: CGFloat
    var rotation: CGFloat
    var isSelected: Bool = false
    
    init(emoji: String, position: CGPoint, size: CGFloat = 60.0, rotation: CGFloat = 0.0) {
        self.emoji = emoji
        self.position = position
        self.size = size
        self.rotation = rotation
    }
}