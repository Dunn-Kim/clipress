import Foundation
import Testing
@testable import MagicClipCore

@Test func parsesSearchOutput() {
    let done = """
        {"crf":38.0,"from_cache":false,"predicted_encode_percent":90.1,"predicted_encode_seconds":9.0,"predicted_encode_size":1,"type":"sample-encode-done","vmaf":90.3}
        {"crf":30.0,"from_cache":false,"predicted_encode_percent":41.25,"predicted_encode_seconds":13.0,"predicted_encode_size":2,"type":"crf-search-done","vmaf":96.1}
        """
    #expect(parseSearch(done) == .found(quality: 30, videoPercent: 41.25))
    #expect(parseSearch(#"{"message":"Failed to find a suitable crf","type":"crf-search-error"}"#) == .noSuitable)
    #expect(parseSearch("") == nil)
}

@Test func encodeArgsKeepCoverArtAndSkipNeedlessFlags() {
    let part = URL(filePath: "/v/o.part")
    let job = Job(videoIndex: 0, container: .mp4, output: part, gop: 300, dataStreams: 0)
    let fast = encodeArgs(input: mp4, output: part, job: job, mode: .fast, quality: 62)
    #expect(fast.contains("-c:V") && !fast.contains("-c:v"))
    #expect(fast.contains("hvc1") && fast.contains("-dn"))
    #expect(!fast.contains("+faststart") && !fast.contains("-map_metadata"))
    #expect(!fast.contains("-movflags"), "MP4에 use_metadata_tags를 쓰면 커버 아트가 사라진다")
    let movArgs = encodeArgs(input: mov, output: part, job: Job(videoIndex: 0, container: .mp4, output: part, gop: 300, dataStreams: 1), mode: .max, quality: 30)
    #expect(movArgs.contains("+use_metadata_tags"))
    let svt = encodeArgs(input: mkv, output: part, job: Job(videoIndex: 0, container: .mkv, output: part, gop: 240, dataStreams: 0), mode: .max, quality: 31)
    #expect(svt.contains("scd=1:crf=31:tune=0:enable-variance-boost=1:enable-qm=1:qm-min=0"))
    #expect(!svt.contains("hvc1") && !svt.contains("-movflags"))
}
