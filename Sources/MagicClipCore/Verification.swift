import Foundation

/// 결과물을 받아들일지 정하는 기준.

/// 결과 파일이 원본의 80%를 넘으면 원본을 유지한다.
let maxSizeRatio = 0.8

/// 비디오 스트림만 바뀌므로, 나머지 스트림 바이트는 그대로 둔 채 파일 전체 크기를 예측한다.
/// 탐색 단계와 최종 판정이 같은 "파일 전체" 기준을 쓰도록 한 곳에 둔다.
func predictedFileSize(fileSize: Int64, videoBytes: Int64, videoPercent: Double) -> Int64 {
    fileSize - Int64(Double(videoBytes) * (1 - videoPercent / 100))
}

func passesSizeGate(_ size: Int64, original: Int64) -> Bool {
    Double(size) <= Double(original) * maxSizeRatio
}

/// 결과 파일이 원본과 같은 영상인지 본다. 문제가 있으면 이유, 없으면 nil.
func verify(original: Probe, originalVideoPackets: Int, output: Probe, outputVideoPackets: Int) -> String? {
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
