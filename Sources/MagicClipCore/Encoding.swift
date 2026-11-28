import Foundation

/// 인코더 설정. ab-av1 탐색과 최종 인코딩이 같은 설정을 쓰도록 한곳에 둔다.

public enum Mode: Sendable {
    /// VideoToolbox HEVC 하드웨어 인코딩.
    case fast
    /// SVT-AV1 소프트웨어 인코딩.
    case max
}

let svtPreset = "4"
let svtParams = ["tune=0", "enable-variance-boost=1", "enable-qm=1", "qm-min=0"]
/// 샘플 평균 VMAF가 전체 파일보다 1.5–2.7점 높게 나온다는 보고가 있어 목표 95에 1점 마진을 둔다.
let minVMAF = "96"

func searchArgs(input: URL, mode: Mode, gop: Int, tempDir: URL) -> [String] {
    var args = [
        "crf-search", "-i", input.path,
        "--min-vmaf", minVMAF,
        // 비디오 스트림이 이 비율을 넘으면 파일 전체도 기준을 넘는다. ab-av1 기본값은 80이라 같은 상수를 넘겨야 한다.
        "--max-encoded-percent", "\(Int(maxSizeRatio * 100))",
        "--sample-every", "12m",
        "--crf-increment", "1",
        // VMAF를 4프레임마다 계산한다. 1080p 53분 파일 실측: 탐색 297초 → 165초, 고른 품질값 동일, VMAF 차이 0.02.
        "--vmaf", "n_subsample=4",
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

enum SearchResult: Equatable {
    case found(quality: Double, videoPercent: Double)
    case noSuitable
}

/// `ab-av1 crf-search --stdout-format json`의 마지막 줄(crf-search-done / crf-search-error)을 읽는다.
/// 둘 다 아니면 nil.
func parseSearch(_ stdout: String) -> SearchResult? {
    struct Line: Decodable {
        var type: String
        var crf: Double?
        var predictedEncodePercent: Double?
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    guard let last = stdout.split(separator: "\n").last,
          let line = try? decoder.decode(Line.self, from: Data(last.utf8)) else { return nil }
    switch line.type {
    case "crf-search-done":
        guard let crf = line.crf, let percent = line.predictedEncodePercent else { return nil }
        return .found(quality: crf, videoPercent: percent)
    case "crf-search-error":
        return .noSuitable
    default:
        return nil
    }
}

/// 최종 인코딩의 입력·스트림 매핑·코덱·출력 인자. 프로세스 수준 옵션(-nostdin, -progress 등)은 `Tools.encode`가 붙인다.
func encodeArgs(input: URL, output: URL, job: Job, mode: Mode, quality: Double) -> [String] {
    let q = String(format: "%g", quality)
    var args = ["-i", input.path, "-map", "0", "-dn", "-c", "copy"]
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
    args += ["-f", job.container.muxer, output.path]
    return args
}
