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
        try await run(ffprobe, ["-v", "error", "-select_streams", "\(stream)", "-show_entries", "packet=size,flags", "-of", "csv=p=0", url.path]) { line in
            guard let size = packetSize(line) else { return }
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

    /// `-progress` 블록(약 0.5초마다)이 끝날 때마다 진행률·속도를 `progress`에 넘긴다.
    func encode(_ args: [String], duration: Double, progress: @escaping (EncodeProgress) -> Void) async throws {
        let global = ["-nostdin", "-y", "-hide_banner", "-v", "error", "-progress", "pipe:1", "-nostats"]
        var current = EncodeProgress()
        try await run(ffmpeg, global + args) { line in
            if current.apply(line, duration: duration) { progress(current) }
        }
    }

    /// 비디오 전체를 디코드한다. -xerror: 디코드 오류가 하나라도 있으면 실패한다.
    func checkDecodes(_ url: URL) async throws {
        try await run(ffmpeg, ["-nostdin", "-v", "error", "-xerror", "-i", url.path, "-map", "0:V:0", "-f", "null", "-"])
    }
}

extension EncodeProgress {
    /// ffmpeg `-progress` 출력 한 줄(key=value)을 반영한다. 블록 끝(`progress=`)이면 true.
    mutating func apply(_ line: String, duration: Double) -> Bool {
        let parts = line.split(separator: "=", maxSplits: 1)
        guard parts.count == 2 else { return false }
        let value = parts[1].trimmingCharacters(in: .whitespaces)
        switch parts[0] {
        case "out_time_us":
            if duration > 0, let us = Double(value) { fraction = min(max(us / 1_000_000 / duration, 0), 1) }
        case "fps":
            fps = Double(value)
        case "speed":
            speed = Double(value.dropLast())  // "2.35x". 아직 모르면 "N/A" → nil
        case "progress":
            // 남은 재생 길이 ÷ 배속
            if duration > 0, let speed, speed > 0 { eta = duration * (1 - fraction) / speed }
            return true
        default:
            break
        }
        return false
    }
}

/// ffprobe `packet=size,flags` 한 줄("1234,K__")의 크기. 숫자가 아닌 줄과 버려지는 패킷은 nil.
/// D(discard) 패킷은 MP4 편집 목록 밖(음수 시각)이라 디코더가 내보내지 않는다. 세면 결과와 프레임 수가 어긋난다.
func packetSize(_ line: String) -> Int64? {
    let fields = line.split(separator: ",", omittingEmptySubsequences: false)
    guard fields.count > 1, !fields[1].contains("D") else { return nil }
    return Int64(fields[0])
}

func ffmpegVersion(_ text: String) -> (Int, Int)? {
    guard let match = text.firstMatch(of: /ffmpeg version n?(\d+)\.(\d+)/),
          let major = Int(match.1), let minor = Int(match.2) else { return nil }
    return (major, minor)
}
