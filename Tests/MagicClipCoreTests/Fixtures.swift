import Foundation
import Testing
@testable import MagicClipCore

/// Fixtures/*.json은 실제 ffprobe 출력이다. dv_p5_mkv.json만 ffmpeg로 DV 파일을 만들 수 없어
/// sdr_mkv.json에 ffprobe 형식의 DOVI configuration record를 덧붙인 것이다.
func fixture(_ name: String) throws -> Probe {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Probe.decode(Data(contentsOf: url))
}

let mkv = URL(filePath: "/v/movie.mkv")
let mp4 = URL(filePath: "/v/clip.mp4")
let mov = URL(filePath: "/v/IMG_0001.MOV")
