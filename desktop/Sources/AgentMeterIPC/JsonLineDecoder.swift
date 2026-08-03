import Foundation

public struct JsonLineDecoder: Sendable {
    private var buffer = Data()
    private let maximumBytes: Int

    public init(maximumBytes: Int = 65_536) {
        precondition(maximumBytes > 0)
        self.maximumBytes = maximumBytes
    }

    public mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let frameLength = buffer.distance(from: buffer.startIndex, to: newline) + 1
            guard frameLength <= maximumBytes else { throw BridgeClientError.frameTooLarge }
            let frame = buffer[..<newline]
            guard String(data: frame, encoding: .utf8) != nil else {
                throw BridgeClientError.invalidFrame
            }
            frames.append(Data(frame))
            buffer.removeSubrange(...newline)
        }
        guard buffer.count < maximumBytes else { throw BridgeClientError.frameTooLarge }
        return frames
    }

    public mutating func finish() throws {
        guard buffer.isEmpty else { throw BridgeClientError.invalidFrame }
    }
}
