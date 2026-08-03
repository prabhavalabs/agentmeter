import Foundation
import Testing
@testable import AgentMeterIPC

@Test func decoderHandlesSplitAndCombinedFrames() throws {
    var decoder = JsonLineDecoder(maximumBytes: 65_536)
    #expect(try decoder.append(Data("{\"schema".utf8)).isEmpty)
    let frames = try decoder.append(Data("Version\":1}\n{\"schemaVersion\":1}\n".utf8))

    #expect(frames.count == 2)
    #expect(String(decoding: frames[0], as: UTF8.self) == "{\"schemaVersion\":1}")
}

@Test func decoderRejectsInvalidUtf8AndOversizedLines() throws {
    var invalid = JsonLineDecoder()
    #expect(throws: BridgeClientError.invalidFrame) {
        try invalid.append(Data([0xFF, 0x0A]))
    }

    var oversized = JsonLineDecoder(maximumBytes: 8)
    #expect(throws: BridgeClientError.frameTooLarge) {
        try oversized.append(Data(repeating: 0x61, count: 8))
    }
}

@Test func decoderRequiresCleanEndOfStream() throws {
    var decoder = JsonLineDecoder()
    _ = try decoder.append(Data("{}".utf8))

    #expect(throws: BridgeClientError.invalidFrame) {
        try decoder.finish()
    }
}
