import Foundation

/// 외부 도구(ffprobe·ab-av1·ffmpeg) 호출. 명령 인자와 출력 형식은 여기서만 다룬다.
/// 개인용이라 번들하지 않고 Homebrew ffmpeg와 cargo ab-av1을 그대로 쓴다.
public struct Tools: Sendable {
    var ffmpeg = URL(filePath: "/opt/homebrew/bin/ffmpeg")
    var ffprobe = URL(filePath: "/opt/homebrew/bin/ffprobe")
    var abav1 = URL.homeDirectory.appending(path: ".cargo/bin/ab-av1")

    public init() {}

    /// 실행할 수 없는 이유. 문제가 없으면 nil.
    public func problem() async -> String? {
        for tool in [ffmpeg, ffprobe, abav1] where !FileManager.default.isExecutableFile(atPath: tool.path) {
            return "\(tool.path) 없음 (brew install ffmpeg, cargo install ab-av1)"
        }
        let text = (try? await run(ffmpeg, ["-hide_banner", "-version"]).text) ?? ""
        guard let version = ffmpegVersion(text) else { return "ffmpeg 버전 확인 불가" }
        // HDR 메타데이터 자동 전달(7.0), VT 소수 품질값(8.1) 등이 버전에 묶여 있다.
        return version >= (8, 1) ? nil : "ffmpeg \(version.0).\(version.1): 8.1 이상 필요"
    }

    func probe(_ url: URL) async throws -> Probe {
        try Probe.decode(try await run(ffprobe, ["-v", "error", "-show_format", "-show_streams", "-of", "json", url.path]).out)
    }

    /// 디코드 없이 패킷만 읽어 비디오 스트림 바이트 수와 프레임(패킷) 수를 센다.
    func videoPackets(_ url: URL, stream: Int) async throws -> (bytes: Int64, count: Int) {
        var bytes: Int64 = 0, count = 0
        try await run(ffprobe, ["-v", "error", "-select_streams", "\(stream)", "-show_entries", "packet=size", "-of", "csv=p=0", url.path]) { line in
            guard let size = Int64(line.prefix { $0.isNumber }) else { return }
            bytes += size
            count += 1
        }
        return (bytes, count)
    }

    func search(_ input: URL, mode: Mode, gop: Int, tempDir: URL) async throws -> SearchResult {
        let result = try await run(abav1, searchArgs(input: input, mode: mode, gop: gop, tempDir: tempDir), check: false)
        guard let parsed = parseSearch(result.text) else {
            throw ToolError(errorDescription: "품질 탐색 실패: \(result.lastErrorLine)")
        }
        return parsed
    }

    /// `-progress`로 받은 인코딩 위치(초)를 `progress`에 넘긴다.
    func encode(_ args: [String], progress: @escaping (Double) -> Void) async throws {
        let global = ["-nostdin", "-y", "-hide_banner", "-v", "error", "-progress", "pipe:1", "-nostats"]
        try await run(ffmpeg, global + args) { line in
            guard line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) else { return }
            progress(us / 1_000_000)
        }
    }

    /// 비디오 전체를 디코드한다. -xerror: 디코드 오류가 하나라도 있으면 실패한다.
    func checkDecodes(_ url: URL) async throws {
        try await run(ffmpeg, ["-nostdin", "-v", "error", "-xerror", "-i", url.path, "-map", "0:V:0", "-f", "null", "-"])
    }
}

func ffmpegVersion(_ text: String) -> (Int, Int)? {
    guard let match = text.firstMatch(of: /ffmpeg version n?(\d+)\.(\d+)/),
          let major = Int(match.1), let minor = Int(match.2) else { return nil }
    return (major, minor)
}
