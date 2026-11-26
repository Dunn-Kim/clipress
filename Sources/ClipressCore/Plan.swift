import Foundation

public enum Mode: Sendable {
    /// VideoToolbox HEVC 하드웨어 인코딩.
    case fast
    /// SVT-AV1 소프트웨어 인코딩.
    case max
}

public enum Container: Sendable, Equatable {
    case mkv, mp4, mov

    public var muxer: String {
        switch self {
        case .mkv: "matroska"
        case .mp4: "mp4"
        case .mov: "mov"
        }
    }

    /// 출력 컨테이너 = 입력 컨테이너. 단, ffmpeg의 mov muxer는 AV1을 받지 않으므로 MOV+AV1은 MP4로 낸다.
    /// MP4/MOV가 아닌 입력(AVI, TS, WebM 등)은 무엇이든 담는 MKV로 낸다.
    public static func output(for input: URL, mode: Mode) -> Container {
        switch input.pathExtension.lowercased() {
        case "mp4", "m4v": .mp4
        case "mov": mode == .max ? .mp4 : .mov
        default: .mkv
        }
    }
}

public struct Job: Sendable, Equatable {
    public var videoIndex: Int
    public var container: Container
    public var gop: Int
    /// MP4/MOV/MKV 출력에서 버리는 데이터 스트림(타임코드, iPhone mebx 등) 수. 결과에 알린다.
    public var dataStreams: Int
}

public enum Decision: Sendable, Equatable {
    case encode(Job)
    case skip(String)
}

/// 인코딩 전에 스킵할 파일을 거른다. HDR·Dolby Vision은 MVP에서 품질 검증 수단이 없어 전부 스킵한다.
public func decide(_ probe: Probe, input: URL, mode: Mode) -> Decision {
    if input.lastPathComponent.contains(".clipress.") { return .skip("clipress 출력 파일") }
    let known: Set = ["video", "audio", "subtitle", "data", "attachment"]
    if probe.streams.contains(where: { !known.contains($0.codecType ?? "") }) {
        return .skip("알 수 없는 스트림 타입")
    }
    let videos = probe.videoStreams
    guard videos.count == 1, let video = videos.first else {
        return .skip("비디오 스트림 \(videos.count)개")
    }
    if video.isDolbyVision { return .skip("Dolby Vision (미지원)") }
    // HDR10+ 는 항상 PQ(smpte2084)라 이 검사에 함께 걸린다.
    if ["smpte2084", "arib-std-b67"].contains(video.colorTransfer ?? "") { return .skip("HDR (미지원)") }
    return .encode(Job(
        videoIndex: video.index,
        container: .output(for: input, mode: mode),
        gop: gop(frameRate: video.avgFrameRate),
        dataStreams: probe.count("data")
    ))
}

/// 키프레임 간격 = 10초.
func gop(frameRate: String?) -> Int {
    let parts = (frameRate ?? "").split(separator: "/").compactMap { Double($0) }
    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return 240 }
    return Int((parts[0] / parts[1] * 10).rounded())
}

public func outputURL(for input: URL, container: Container) -> URL {
    let ext: String
    switch container {
    case .mkv: ext = "mkv"
    case .mov: ext = input.pathExtension
    case .mp4: ext = ["mp4", "m4v"].contains(input.pathExtension.lowercased()) ? input.pathExtension : "mp4"
    }
    return input.deletingPathExtension().appendingPathExtension("clipress").appendingPathExtension(ext)
}

// MARK: - 크기 기준

/// 결과 파일이 원본의 80%를 넘으면 원본을 유지한다.
public let maxSizeRatio = 0.8

/// 비디오 스트림만 바뀌므로, 나머지 스트림 바이트는 그대로 둔 채 파일 전체 크기를 예측한다.
/// 탐색 단계와 최종 판정이 같은 "파일 전체" 기준을 쓰도록 한 곳에 둔다.
public func predictedFileSize(fileSize: Int64, videoBytes: Int64, videoPercent: Double) -> Int64 {
    fileSize - Int64(Double(videoBytes) * (1 - videoPercent / 100))
}

public func passesSizeGate(_ size: Int64, original: Int64) -> Bool {
    Double(size) <= Double(original) * maxSizeRatio
}

// MARK: - 인코더 인자 (ab-av1 탐색과 최종 인코딩이 같은 설정을 쓴다)

let svtPreset = "4"
let svtParams = ["tune=0", "enable-variance-boost=1", "enable-qm=1", "qm-min=0"]
/// 샘플 평균 VMAF가 전체 파일보다 1.5–2.7점 높게 나온다는 보고가 있어 목표 95에 1점 마진을 둔다.
let minVMAF = "96"

public func searchArgs(input: URL, mode: Mode, gop: Int, tempDir: URL) -> [String] {
    var args = [
        "crf-search", "-i", input.path,
        "--min-vmaf", minVMAF,
        "--sample-every", "6m",
        "--crf-increment", "1",
        "--keyint", "\(gop)",
        "--temp-dir", tempDir.path,
        "--stdout-format", "json",
    ]
    switch mode {
    case .fast:
        // ab-av1은 p010le를 받지 않는다. yuv420p10le를 주면 ffmpeg가 VT용 p010le로 자동 변환한다(최종 인코딩과 같은 픽셀).
        args += ["--encoder", "hevc_videotoolbox", "--pix-format", "yuv420p10le",
                 "--enc", "bf=2", "--enc", "profile=main10"]
    case .max:
        args += ["--encoder", "libsvtav1", "--preset", svtPreset, "--scd", "true",
                 "--pix-format", "yuv420p10le"]
        args += svtParams.flatMap { ["--svt", $0] }
    }
    return args
}

public enum SearchResult: Sendable, Equatable {
    case found(quality: Double, videoPercent: Double)
    case noSuitable
    case invalid
}

/// `ab-av1 crf-search --stdout-format json`의 마지막 줄(crf-search-done / crf-search-error)을 읽는다.
public func parseSearch(_ stdout: String) -> SearchResult {
    struct Line: Decodable {
        var type: String
        var crf: Double?
        var predictedEncodePercent: Double?
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let last = stdout.split(separator: "\n").last,
          let line = try? decoder.decode(Line.self, from: Data(last.utf8)) else { return .invalid }
    switch line.type {
    case "crf-search-done":
        guard let crf = line.crf, let percent = line.predictedEncodePercent else { return .invalid }
        return .found(quality: crf, videoPercent: percent)
    case "crf-search-error":
        return .noSuitable
    default:
        return .invalid
    }
}

public func encodeArgs(input: URL, output: URL, job: Job, mode: Mode, quality: Double) -> [String] {
    let q = String(format: "%g", quality)
    var args = [
        "-nostdin", "-y", "-hide_banner", "-v", "error",
        "-i", input.path,
        "-map", "0", "-dn", "-c", "copy",
    ]
    // 대문자 V: 커버 아트(attached pic)는 copy로 두고 실제 비디오만 재인코딩한다.
    switch mode {
    case .fast:
        args += ["-c:V", "hevc_videotoolbox", "-q:V", q, "-bf:V", "2", "-g:V", "\(job.gop)",
                 "-profile:V", "main10", "-pix_fmt:V", "p010le"]
        if job.container != .mkv { args += ["-tag:V", "hvc1"] }
    case .max:
        args += ["-c:V", "libsvtav1", "-preset:V", svtPreset, "-crf:V", q, "-g:V", "\(job.gop)",
                 "-pix_fmt:V", "yuv420p10le",
                 "-svtav1-params:V", (["scd=1", "crf=\(q)"] + svtParams).joined(separator: ":")]
    }
    args += ["-fps_mode:V", "passthrough", "-max_muxing_queue_size", "9999"]
    // MOV(iPhone)의 com.apple.quicktime.* 키(위치·촬영일)를 지킨다. MP4 입력에 쓰면 커버 아트가 사라져서(ffmpeg 9.1 실측) MOV 입력에만 붙인다.
    if input.pathExtension.lowercased() == "mov" { args += ["-movflags", "+use_metadata_tags"] }
    args += ["-progress", "pipe:1", "-nostats", "-f", job.container.muxer, output.path]
    return args
}

// MARK: - 사후 검증

/// 결과 파일이 원본과 같은 영상인지 본다. 문제가 있으면 이유, 없으면 nil.
public func verify(original: Probe, originalVideoPackets: Int, output: Probe, outputVideoPackets: Int) -> String? {
    guard let src = original.videoStreams.first, let dst = output.videoStreams.first else {
        return "비디오 스트림 없음"
    }
    if src.displaySize != dst.displaySize { return "해상도 불일치" }
    if originalVideoPackets != outputVideoPackets {
        return "프레임 수 불일치 (\(originalVideoPackets) → \(outputVideoPackets))"
    }
    if let a = original.duration, let b = output.duration, abs(a - b) > 2 { return "길이 불일치" }
    for type in ["video", "audio", "subtitle", "attachment"] where original.count(type) != output.count(type) {
        return "\(type) 스트림 수 불일치"
    }
    if original.attachedPics != output.attachedPics { return "커버 아트 수 불일치" }
    return nil
}
