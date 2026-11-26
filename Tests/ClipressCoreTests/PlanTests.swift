import Foundation
import Testing
@testable import ClipressCore

/// Fixtures/*.json은 실제 ffprobe 출력이다. dv_p5_mkv.json만 ffmpeg로 DV 파일을 만들 수 없어
/// sdr_mkv.json에 ffprobe 형식의 DOVI configuration record를 덧붙인 것이다.
func fixture(_ name: String) throws -> Probe {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Probe.decode(Data(contentsOf: url))
}

let mkv = URL(filePath: "/v/movie.mkv")
let mp4 = URL(filePath: "/v/clip.mp4")
let mov = URL(filePath: "/v/IMG_0001.MOV")

@Test func sdrMKVIsEncodedAsMKV() throws {
    #expect(decide(try fixture("sdr_mkv"), input: mkv, mode: .max)
        == .encode(Job(videoIndex: 0, container: .mkv, gop: 300, dataStreams: 0)))
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
    #expect(decide(probe, input: mov, mode: .fast) == .encode(Job(videoIndex: 0, container: .mov, gop: 300, dataStreams: 1)))
    guard case .encode(let job) = decide(probe, input: mov, mode: .max) else { Issue.record(); return }
    #expect(job.container == .mp4)
    #expect(outputURL(for: mov, container: job.container).lastPathComponent == "IMG_0001.clipress.mp4")
}

@Test func clipressOutputsAreSkipped() throws {
    #expect(decide(try fixture("sdr_mkv"), input: URL(filePath: "/v/movie.clipress.mkv"), mode: .max)
        == .skip("clipress 출력 파일"))
}

@Test func outputNames() {
    #expect(outputURL(for: mkv, container: .mkv).lastPathComponent == "movie.clipress.mkv")
    #expect(outputURL(for: URL(filePath: "/v/a.webm"), container: .mkv).lastPathComponent == "a.clipress.mkv")
    #expect(outputURL(for: URL(filePath: "/v/a.m4v"), container: .mp4).lastPathComponent == "a.clipress.m4v")
    #expect(outputURL(for: mov, container: .mov).lastPathComponent == "IMG_0001.clipress.MOV")
}

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
    // 40 GB 리먹스, 비디오 25 GB, 비디오 예측 76% → 파일 34 GB(85%)라 인코딩하지 않는다.
    let gb: Int64 = 1_000_000_000
    let predicted = predictedFileSize(fileSize: 40 * gb, videoBytes: 25 * gb, videoPercent: 76)
    #expect(predicted == 34 * gb)
    #expect(!passesSizeGate(predicted, original: 40 * gb))
    #expect(passesSizeGate(32 * gb, original: 40 * gb))
}

@Test func parsesSearchOutput() {
    let done = """
        {"crf":38.0,"from_cache":false,"predicted_encode_percent":90.1,"predicted_encode_seconds":9.0,"predicted_encode_size":1,"type":"sample-encode-done","vmaf":90.3}
        {"crf":30.0,"from_cache":false,"predicted_encode_percent":41.25,"predicted_encode_seconds":13.0,"predicted_encode_size":2,"type":"crf-search-done","vmaf":96.1}
        """
    #expect(parseSearch(done) == .found(quality: 30, videoPercent: 41.25))
    #expect(parseSearch(#"{"message":"Failed to find a suitable crf","type":"crf-search-error"}"#) == .noSuitable)
    #expect(parseSearch("") == .invalid)
}

@Test func encodeArgsKeepCoverArtAndSkipNeedlessFlags() {
    let job = Job(videoIndex: 0, container: .mp4, gop: 300, dataStreams: 0)
    let fast = encodeArgs(input: mp4, output: URL(filePath: "/v/o.part"), job: job, mode: .fast, quality: 62)
    #expect(fast.contains("-c:V") && !fast.contains("-c:v"))
    #expect(fast.contains("hvc1") && fast.contains("-dn") && fast.contains("-nostdin"))
    #expect(!fast.contains("+faststart") && !fast.contains("-map_metadata"))
    #expect(!fast.contains("-movflags"), "MP4에 use_metadata_tags를 쓰면 커버 아트가 사라진다")
    let movArgs = encodeArgs(input: mov, output: URL(filePath: "/v/o.part"), job: Job(videoIndex: 0, container: .mp4, gop: 300, dataStreams: 1), mode: .max, quality: 30)
    #expect(movArgs.contains("+use_metadata_tags"))
    let svt = encodeArgs(input: mkv, output: URL(filePath: "/v/o.part"), job: Job(videoIndex: 0, container: .mkv, gop: 240, dataStreams: 0), mode: .max, quality: 31)
    #expect(svt.contains("scd=1:crf=31:tune=0:enable-variance-boost=1:enable-qm=1:qm-min=0"))
    #expect(!svt.contains("hvc1") && !svt.contains("-movflags"))
}

@Test func parsesFFmpegVersion() throws {
    let release = try #require(ffmpegVersion("ffmpeg version 9.1 Copyright (c) 2000-2026"))
    #expect(release.0 == 9 && release.1 == 1)
    let tagged = try #require(ffmpegVersion("ffmpeg version n8.0.3"))
    #expect(tagged.0 == 8 && tagged.1 == 0)
    #expect(ffmpegVersion("ffmpeg version N-123-gabc") == nil)
}
