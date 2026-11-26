import Foundation
import Testing
@testable import ClipressCore

@Test func sdrMKVIsEncodedAsMKV() throws {
    #expect(decide(try fixture("sdr_mkv"), input: mkv, mode: .max) == .encode(Job(
        videoIndex: 0, container: .mkv, output: URL(filePath: "/v/movie.clipress.mkv"), gop: 300, dataStreams: 0
    )))
}

@Test func hdrAndDolbyVisionAreSkipped() throws {
    #expect(decide(try fixture("hdr10_mkv"), input: mkv, mode: .max) == .skip("HDR (미지원)"))
    #expect(decide(try fixture("dv_p5_mkv"), input: mkv, mode: .fast) == .skip("Dolby Vision (미지원)"))
}

@Test func coverArtIsNotTheVideoStream() throws {
    let probe = try fixture("cover_mp4")
    #expect(probe.attachedPics == 1)
    guard case .encode(let job) = decide(probe, input: mp4, mode: .fast) else { Issue.record(); return }
    #expect(job.videoIndex == 0 && job.container == .mp4)
}

@Test func movKeepsMOVForHEVCButAV1GoesToMP4() throws {
    let probe = try fixture("tmcd_mov")
    #expect(decide(probe, input: mov, mode: .fast) == .encode(Job(
        videoIndex: 0, container: .mov, output: URL(filePath: "/v/IMG_0001.clipress.MOV"), gop: 300, dataStreams: 1
    )))
    guard case .encode(let job) = decide(probe, input: mov, mode: .max) else { Issue.record(); return }
    #expect(job.container == .mp4)
    #expect(job.output.lastPathComponent == "IMG_0001.clipress.mp4")
}

@Test func clipressOutputsAreSkipped() throws {
    #expect(decide(try fixture("sdr_mkv"), input: URL(filePath: "/v/movie.clipress.mkv"), mode: .max)
        == .skip("clipress 출력 파일"))
}

@Test func outputContainerAndName() {
    func name(_ path: String, _ mode: Mode = .fast) -> String {
        let (container, url) = output(for: URL(filePath: path), mode: mode)
        return "\(container.muxer) \(url.lastPathComponent)"
    }
    #expect(name("/v/movie.mkv") == "matroska movie.clipress.mkv")
    #expect(name("/v/a.webm") == "matroska a.clipress.mkv")
    #expect(name("/v/a.m4v") == "mp4 a.clipress.m4v")
    #expect(name("/v/IMG_0001.MOV") == "mov IMG_0001.clipress.MOV")
    #expect(name("/v/IMG_0001.MOV", .max) == "mp4 IMG_0001.clipress.mp4")
}
