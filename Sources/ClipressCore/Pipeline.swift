import Foundation

public enum Outcome: Sendable, Equatable {
    case done(before: Int64, after: Int64, note: String?)
    case skipped(String)
    case failed(String)
}

/// 처리 중인 단계. 인코딩 단계만 진행률과 속도를 안다.
public enum Stage: Sendable, Equatable {
    case analyzing
    case searching
    case encoding(EncodeProgress)
    case verifying
}

public struct EncodeProgress: Sendable, Equatable {
    /// 0...1
    public var fraction: Double = 0
    /// 초당 인코딩 프레임 수.
    public var fps: Double?
    /// 재생 속도 대비 배속 (2.0 = 실시간의 2배).
    public var speed: Double?
    /// 인코딩이 끝날 때까지 남은 시간(초). 배속을 알아야 계산된다.
    public var eta: Double?
}

/// 파일 하나를 분석 → 품질 탐색 → 인코딩 → 검증 → 이름 변경 순서로 처리한다. 원본은 건드리지 않는다.
/// 단계 순서만 다루고, 판단은 Routing·Verification에, 도구 호출은 Tools에 맡긴다.
public func compress(
    _ input: URL, mode: Mode, tools: Tools, status: @escaping @Sendable (Stage) -> Void
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
        status(.analyzing)
        let probe = try await tools.probe(input)
        let job: Job
        switch decide(probe, input: input, mode: mode) {
        case .skip(let reason): return .skipped(reason)
        case .encode(let decided): job = decided
        }
        if fm.fileExists(atPath: job.output.path) { return .skipped("출력 파일이 이미 있음") }
        let fileSize = try size(of: input)
        let free = try input.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage ?? 0
        if free < fileSize { return .failed("디스크 공간 부족") }
        let video = try await tools.videoPackets(input, stream: job.videoIndex)

        status(.searching)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        let quality: Double, videoPercent: Double
        switch try await tools.search(input, mode: mode, gop: job.gop, tempDir: temp) {
        case .found(let q, let percent): (quality, videoPercent) = (q, percent)
        case .noSuitable: return .skipped("목표 화질을 80% 이하 크기로 낼 수 없음")
        }
        let predicted = predictedFileSize(fileSize: fileSize, videoBytes: video.bytes, videoPercent: videoPercent)
        guard passesSizeGate(predicted, original: fileSize) else {
            return .skipped("예상 크기 \(percent(predicted, of: fileSize))%: 절감 부족")
        }

        let partURL = job.output.appendingPathExtension("part")
        part = partURL
        status(.encoding(EncodeProgress()))
        try await tools.encode(encodeArgs(input: input, output: partURL, job: job, mode: mode, quality: quality),
                               duration: probe.duration ?? 0) { status(.encoding($0)) }

        status(.verifying)
        try await tools.checkDecodes(partURL)
        let result = try await tools.probe(partURL)
        let resultPackets = try await tools.videoPackets(partURL, stream: result.videoStreams.first?.index ?? 0)
        if let problem = verify(original: probe, originalVideoPackets: video.count, output: result, outputVideoPackets: resultPackets.count) {
            return .failed("검증 실패: \(problem)")
        }
        let after = try size(of: partURL)
        guard passesSizeGate(after, original: fileSize) else {
            return .skipped("결과 크기 \(percent(after, of: fileSize))%: 절감 부족")
        }

        try fm.moveItem(at: partURL, to: job.output)
        part = nil
        let attributes = try fm.attributesOfItem(atPath: input.path)
        try fm.setAttributes(
            [.creationDate: attributes[.creationDate], .modificationDate: attributes[.modificationDate]].compactMapValues { $0 },
            ofItemAtPath: job.output.path
        )
        return .done(before: fileSize, after: after, note: job.dataStreams > 0 ? "데이터 스트림 \(job.dataStreams)개 제외" : nil)
    } catch {
        return .failed(Task.isCancelled ? "취소됨" : error.localizedDescription)
    }
}

private func size(of url: URL) throws -> Int64 {
    Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
}

private func percent(_ part: Int64, of whole: Int64) -> Int {
    Int((Double(part) / Double(whole) * 100).rounded())
}
