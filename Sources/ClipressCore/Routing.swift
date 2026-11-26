import Foundation

/// 파일을 인코딩할지, 한다면 어디로 낼지 정한다.

enum Container: Equatable {
    case mkv, mp4, mov

    var muxer: String {
        switch self {
        case .mkv: "matroska"
        case .mp4: "mp4"
        case .mov: "mov"
        }
    }
}

struct Job: Equatable {
    var videoIndex: Int
    var container: Container
    var output: URL
    var gop: Int
    /// 출력에서 버리는 데이터 스트림(타임코드, iPhone mebx 등) 수. 결과에 알린다.
    var dataStreams: Int
}

enum Decision: Equatable {
    case encode(Job)
    case skip(String)
}

/// 결과 파일 이름 = 원본 이름 + 접미사. 이 접미사로 끝나는 파일은 다시 압축하지 않는다.
let outputSuffix = "-pressed"

/// HDR·Dolby Vision은 MVP에서 품질 검증 수단이 없어 전부 스킵한다.
func decide(_ probe: Probe, input: URL, mode: Mode) -> Decision {
    if input.deletingPathExtension().lastPathComponent.hasSuffix(outputSuffix) { return .skip("clipress 출력 파일") }
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
    let (container, url) = output(for: input, mode: mode)
    return .encode(Job(
        videoIndex: video.index,
        container: container,
        output: url,
        gop: gop(frameRate: video.avgFrameRate),
        dataStreams: probe.count("data")
    ))
}

/// 출력 컨테이너 = 입력 컨테이너. ffmpeg의 mov muxer는 AV1을 받지 않아 MOV+AV1은 MP4로,
/// MP4/MOV가 아닌 입력(AVI, TS, WebM 등)은 무엇이든 담는 MKV로 낸다.
func output(for input: URL, mode: Mode) -> (Container, URL) {
    let ext = input.pathExtension
    let (container, outputExt): (Container, String) = switch ext.lowercased() {
    case "mp4", "m4v": (.mp4, ext)
    case "mov": mode == .max ? (.mp4, "mp4") : (.mov, ext)
    default: (.mkv, "mkv")
    }
    let name = input.deletingPathExtension().lastPathComponent + outputSuffix
    return (container, input.deletingLastPathComponent().appending(path: name).appendingPathExtension(outputExt))
}

/// 키프레임 간격 = 10초.
func gop(frameRate: String?) -> Int {
    let parts = (frameRate ?? "").split(separator: "/").compactMap { Double($0) }
    guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return 240 }
    return Int((parts[0] / parts[1] * 10).rounded())
}
