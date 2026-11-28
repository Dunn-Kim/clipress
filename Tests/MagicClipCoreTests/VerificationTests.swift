import Foundation
import Testing
@testable import MagicClipCore

@Test func rotatedPhoneVideoPassesVerification() throws {
    let original = try fixture("rotated_mp4"), output = try fixture("rotated_out_mp4")
    #expect(original.videoStreams[0].displaySize == [1080, 1920])
    #expect(verify(original: original, originalVideoPackets: 360, output: output, outputVideoPackets: 360) == nil)
}

@Test func verificationCatchesMissingFramesAndStreams() throws {
    let original = try fixture("cover_mp4")
    #expect(verify(original: original, originalVideoPackets: 360, output: original, outputVideoPackets: 359) != nil)
    #expect(verify(original: original, originalVideoPackets: 360, output: try fixture("rotated_mp4"), outputVideoPackets: 360) != nil)
}

@Test func sizeGateUsesWholeFile() {
    // 40 GB 리먹스, 비디오 25 GB, 비디오 예측 87.5% → 파일 36.875 GB(92%)라 인코딩하지 않는다.
    let gb: Int64 = 1_000_000_000
    let predicted = predictedFileSize(fileSize: 40 * gb, videoBytes: 25 * gb, videoPercent: 87.5)
    #expect(predicted == 36_875_000_000)
    #expect(!passesSizeGate(predicted, original: 40 * gb))
    #expect(passesSizeGate(34 * gb, original: 40 * gb))  // 정확히 85%
}
