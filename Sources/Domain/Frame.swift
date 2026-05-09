import Foundation

public struct Frame: Sendable, Equatable {
    public let presentationTime: TimeInterval
    public let data: Data

    public init(presentationTime: TimeInterval, data: Data) {
        self.presentationTime = presentationTime
        self.data = data
    }
}
