import Foundation

/// 개인용이라 번들하지 않고 Homebrew ffmpeg와 cargo ab-av1을 그대로 쓴다.
public struct Tools: Sendable {
    public var ffmpeg = URL(filePath: "/opt/homebrew/bin/ffmpeg")
    public var ffprobe = URL(filePath: "/opt/homebrew/bin/ffprobe")
    public var abav1 = URL.homeDirectory.appending(path: ".cargo/bin/ab-av1")

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
}

public func ffmpegVersion(_ text: String) -> (Int, Int)? {
    guard let match = text.firstMatch(of: /ffmpeg version n?(\d+)\.(\d+)/),
          let major = Int(match.1), let minor = Int(match.2) else { return nil }
    return (major, minor)
}

public enum Outcome: Sendable, Equatable {
    case done(before: Int64, after: Int64, note: String?)
    case skipped(String)
    case failed(String)
}

/// 파일 하나를 분석 → 품질 탐색 → 인코딩 → 검증 → 이름 변경까지 처리한다. 원본은 건드리지 않는다.
public func compress(
    _ input: URL, mode: Mode, tools: Tools, status: @escaping @Sendable (String) -> Void
) async -> Outcome {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appending(path: "clipress-\(UUID().uuidString)")
    var part: URL?
    // 실패·취소 시 수십 GB짜리 임시 파일을 남기지 않는다.
    defer {
        try? fm.removeItem(at: temp)
        if let part { try? fm.removeItem(at: part) }
    }
    do {
        status("분석 중")
        let probe = try Probe.decode(try await run(tools.ffprobe, probeArgs(input)).out)
        let job: Job
        switch decide(probe, input: input, mode: mode) {
        case .skip(let reason): return .skipped(reason)
        case .encode(let decided): job = decided
        }
        let output = outputURL(for: input, container: job.container)
        if fm.fileExists(atPath: output.path) { return .skipped("출력 파일이 이미 있음") }
        let fileSize = try size(of: input)
        let free = try input.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? 0
        if free < fileSize { return .failed("디스크 공간 부족") }
        let video = try await videoPackets(input, stream: job.videoIndex, tools: tools)

        status("품질 탐색 중")
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        let searched = try await run(tools.abav1, searchArgs(input: input, mode: mode, gop: job.gop, tempDir: temp), check: false)
        let quality: Double, videoPercent: Double
        switch parseSearch(searched.text) {
        case .found(let q, let percent): (quality, videoPercent) = (q, percent)
        case .noSuitable: return .skipped("목표 화질을 80% 이하 크기로 낼 수 없음")
        case .invalid: return .failed("품질 탐색 실패: \(searched.lastErrorLine)")
        }
        let predicted = predictedFileSize(fileSize: fileSize, videoBytes: video.bytes, videoPercent: videoPercent)
        guard passesSizeGate(predicted, original: fileSize) else {
            return .skipped("예상 크기 \(percent(predicted, of: fileSize))%: 절감 부족")
        }

        let partURL = output.appendingPathExtension("part")
        part = partURL
        let duration = probe.duration ?? 0
        status("인코딩 0%")
        try await run(tools.ffmpeg, encodeArgs(input: input, output: partURL, job: job, mode: mode, quality: quality)) { line in
            guard duration > 0, line.hasPrefix("out_time_us="), let us = Double(line.dropFirst(12)) else { return }
            status("인코딩 \(Int(min(us / 1_000_000 / duration, 1) * 100))%")
        }

        status("검증 중")
        // -xerror: 디코드 오류가 하나라도 있으면 종료 코드로 실패한다.
        try await run(tools.ffmpeg, ["-nostdin", "-v", "error", "-xerror", "-i", partURL.path, "-map", "0:V:0", "-f", "null", "-"])
        let outProbe = try Probe.decode(try await run(tools.ffprobe, probeArgs(partURL)).out)
        let outPackets = try await videoPackets(partURL, stream: outProbe.videoStreams.first?.index ?? 0, tools: tools)
        if let problem = verify(original: probe, originalVideoPackets: video.count, output: outProbe, outputVideoPackets: outPackets.count) {
            return .failed("검증 실패: \(problem)")
        }
        let after = try size(of: partURL)
        guard passesSizeGate(after, original: fileSize) else {
            return .skipped("결과 크기 \(percent(after, of: fileSize))%: 절감 부족")
        }

        try fm.moveItem(at: partURL, to: output)
        part = nil
        let attributes = try fm.attributesOfItem(atPath: input.path)
        try fm.setAttributes(
            [.creationDate: attributes[.creationDate], .modificationDate: attributes[.modificationDate]].compactMapValues { $0 },
            ofItemAtPath: output.path
        )
        return .done(before: fileSize, after: after, note: job.dataStreams > 0 ? "데이터 스트림 \(job.dataStreams)개 제외" : nil)
    } catch {
        return .failed(Task.isCancelled ? "취소됨" : "\(error)")
    }
}

func probeArgs(_ url: URL) -> [String] {
    ["-v", "error", "-show_format", "-show_streams", "-of", "json", url.path]
}

/// 디코드 없이 패킷만 읽어 비디오 스트림 바이트 수와 프레임(패킷) 수를 센다.
func videoPackets(_ url: URL, stream: Int, tools: Tools) async throws -> (bytes: Int64, count: Int) {
    let text = try await run(tools.ffprobe, ["-v", "error", "-select_streams", "\(stream)", "-show_entries", "packet=size", "-of", "csv=p=0", url.path]).text
    var bytes: Int64 = 0, count = 0
    for line in text.split(separator: "\n") {
        guard let n = Int64(line.prefix { $0.isNumber }) else { continue }
        bytes += n
        count += 1
    }
    return (bytes, count)
}

func size(of url: URL) throws -> Int64 {
    Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
}

func percent(_ part: Int64, of whole: Int64) -> Int {
    Int((Double(part) / Double(whole) * 100).rounded())
}

// MARK: - 외부 프로세스

struct ToolError: Error, CustomStringConvertible {
    var description: String
}

struct RunResult {
    var out: Data
    var err: String
    var status: Int32
    var text: String { String(decoding: out, as: UTF8.self) }
    var lastErrorLine: String { err.split(separator: "\n").last.map(String.init) ?? "종료 코드 \(status)" }
}

/// 도구를 실행한다. Task 취소 시 SIGINT로 중단한다. `onLine`을 주면 stdout을 줄 단위로 넘기고 쌓지 않는다.
@discardableResult
func run(
    _ tool: URL, _ args: [String], check: Bool = true, onLine: (@Sendable (String) -> Void)? = nil
) async throws -> RunResult {
    try Task.checkCancellation()
    let process = Process()
    process.executableURL = tool
    process.arguments = args
    var env = ProcessInfo.processInfo.environment
    // ab-av1은 ffmpeg/ffprobe를 PATH에서 찾는다.
    env["PATH"] = "/opt/homebrew/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
    process.environment = env
    process.standardInput = FileHandle.nullDevice
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err
    let buffer = OutputBuffer(onLine: onLine)
    out.fileHandleForReading.readabilityHandler = { buffer.appendOut($0.availableData) }
    err.fileHandleForReading.readabilityHandler = { buffer.appendErr($0.availableData) }

    let running = process
    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    } onCancel: {
        guard running.isRunning else { return }
        // 자식(ab-av1이 띄운 ffmpeg)까지 멈추도록 프로세스 그룹에 보낸다.
        let pid = running.processIdentifier
        if getpgid(pid) == pid { kill(-pid, SIGINT) } else { running.interrupt() }
    }

    out.fileHandleForReading.readabilityHandler = nil
    err.fileHandleForReading.readabilityHandler = nil
    buffer.appendOut(out.fileHandleForReading.readDataToEndOfFile())
    buffer.appendErr(err.fileHandleForReading.readDataToEndOfFile())
    let result = buffer.result(status: process.terminationStatus)
    try Task.checkCancellation()
    if check, result.status != 0 {
        throw ToolError(description: "\(tool.lastPathComponent): \(result.lastErrorLine)")
    }
    return result
}

private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = Data()
    private var pending = ""
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)?) { self.onLine = onLine }

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.withLock {
            guard let onLine else { return out.append(data) }
            pending += String(decoding: data, as: UTF8.self)
            while let newline = pending.firstIndex(of: "\n") {
                onLine(String(pending[..<newline]))
                pending.removeSubrange(...newline)
            }
        }
    }

    /// 몇 시간짜리 진행 표시가 쌓이지 않도록 끝부분만 남긴다.
    func appendErr(_ data: Data) {
        lock.withLock {
            err.append(data)
            if err.count > 16_384 { err = Data(err.suffix(8_192)) }
        }
    }

    func result(status: Int32) -> RunResult {
        lock.withLock { RunResult(out: out, err: String(decoding: err, as: UTF8.self), status: status) }
    }
}
