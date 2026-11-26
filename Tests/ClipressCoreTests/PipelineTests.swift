import Foundation
import Synchronization
import Testing
@testable import ClipressCore

/// 실제 ffmpeg·ab-av1로 짧은 클립을 끝까지 처리한다. 도구가 없으면 건너뛴다.
@Suite(.serialized, .enabled(if: toolsInstalled))
final class PipelineTests {
    let tools = Tools()
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "clipress-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }

    /// 압축 여지가 크도록 x264 crf 10으로 만든 원본.
    func clip(_ name: String, seconds: Int = 4, size: String = "1280x720", extra: [String] = []) async throws -> URL {
        let url = dir.appending(path: name)
        try await tools.run(tools.ffmpeg, ["-nostdin", "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc2=size=\(size):rate=24:duration=\(seconds)",
            "-f", "lavfi", "-i", "sine=duration=\(seconds)"] + extra
            + ["-c:v", "libx264", "-crf", "10", "-c:a", "aac", url.path])
        return url
    }

    func leftovers() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".part") }
    }

    @Test func fastModeKeepsRotationCoverArtAndDates() async throws {
        let plain = try await clip("plain.mp4")
        let cover = dir.appending(path: "cover.png")
        try await tools.run(tools.ffmpeg, ["-nostdin", "-v", "error", "-f", "lavfi", "-i", "color=red:size=64x64", "-frames:v", "1", cover.path])
        let input = dir.appending(path: "phone.mp4")
        try await tools.run(tools.ffmpeg, ["-nostdin", "-v", "error", "-display_rotation:v:0", "90", "-i", plain.path, "-i", cover.path,
            "-map", "0", "-map", "1", "-c", "copy", "-disposition:v:1", "attached_pic", input.path])
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: input.path)

        let stages = Mutex<[Stage]>([])
        let outcome = await compress(input, mode: .fast, tools: tools) { stage in stages.withLock { $0.append(stage) } }
        guard case .done(let before, let after, _) = outcome else { Issue.record("\(outcome)"); return }
        #expect(after < before)
        // 진행률 막대와 속도계가 쓰는 값이 실제 인코딩에서 보고된다.
        let reported = stages.withLock { $0 }
        #expect(reported.first == .analyzing && reported.last == .verifying)
        let encoding = reported.compactMap { if case .encoding(let p) = $0 { p } else { nil } }
        #expect((encoding.last?.fraction ?? 0) > 0.9)
        #expect(encoding.contains { $0.fps != nil && $0.speed != nil && $0.eta != nil })
        let output = dir.appending(path: "phone-pressed.mp4")
        let result = try await tools.probe(output)
        #expect(result.videoStreams.first?.displaySize == [720, 1280])
        #expect(result.attachedPics == 1)
        #expect(try FileManager.default.attributesOfItem(atPath: output.path)[.modificationDate] as? Date == date)
        #expect(try leftovers().isEmpty)
    }

    @Test func fastModeOnMOVDropsTimecodeAndSaysSo() async throws {
        let input = try await clip("IMG_0001.MOV", extra: ["-timecode", "01:00:00:00"])
        let outcome = await compress(input, mode: .fast, tools: tools) { _ in }
        guard case .done(_, _, let note) = outcome else { Issue.record("\(outcome)"); return }
        #expect(note == "데이터 스트림 1개 제외")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "IMG_0001-pressed.MOV").path))
    }

    @Test func maxModeKeepsSubtitlesInMKV() async throws {
        let srt = dir.appending(path: "sub.srt")
        try "1\n00:00:00,000 --> 00:00:02,000\n안녕\n".write(to: srt, atomically: true, encoding: .utf8)
        let input = try await clip("movie.mkv", size: "640x360", extra: ["-i", srt.path, "-map", "0", "-map", "1", "-map", "2", "-c:s", "srt"])
        let outcome = await compress(input, mode: .max, tools: tools) { _ in }
        guard case .done = outcome else { Issue.record("\(outcome)"); return }
        let result = try await tools.probe(dir.appending(path: "movie-pressed.mkv"))
        #expect(result.count("subtitle") == 1)
        #expect(String(decoding: try await tools.run(tools.ffprobe, ["-v", "error", "-select_streams", "V:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0", dir.appending(path: "movie-pressed.mkv").path]).out, as: UTF8.self).hasPrefix("av1"))
    }

    @Test func cancelStopsChildrenAndCleansUp() async throws {
        let input = try await clip("long-cancel-target.mkv", seconds: 20, size: "1920x1080")
        let tools = tools
        let task = Task { await compress(input, mode: .max, tools: tools) { _ in } }
        try await Task.sleep(for: .seconds(4))
        task.cancel()
        #expect(await task.value == .failed("취소됨"))
        try await Task.sleep(for: .seconds(1))
        let ps = try await tools.run(URL(filePath: "/usr/bin/pgrep"), ["-f", "long-cancel-target"], check: false)
        #expect(ps.text.isEmpty, "남은 자식 프로세스: \(ps.text)")
        #expect(try leftovers().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "long-cancel-target-pressed.mkv").path))
    }
}

let toolsInstalled: Bool = {
    let tools = Tools()
    return [tools.ffmpeg, tools.ffprobe, tools.abav1].allSatisfy { FileManager.default.isExecutableFile(atPath: $0.path) }
}()
