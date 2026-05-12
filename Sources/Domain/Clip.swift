import Foundation

public struct Clip: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let recordedAt: Date
    public let frames: [Frame]
    public let duration: TimeInterval

    public init(id: UUID, recordedAt: Date, frames: [Frame], duration: TimeInterval) {
        self.id = id
        self.recordedAt = recordedAt
        self.frames = frames
        self.duration = duration
    }
}
