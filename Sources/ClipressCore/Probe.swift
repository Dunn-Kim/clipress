import Foundation

/// `ffprobe -show_format -show_streams -of json` 결과 중 clipress가 쓰는 부분.
struct Probe: Decodable {
    var streams: [Stream]
    var format: Format

    struct Stream: Decodable {
        var index: Int
        var codecType: String?
        var width: Int?
        var height: Int?
        var avgFrameRate: String?
        var colorTransfer: String?
        var disposition: Disposition?
        var sideDataList: [SideData]?

        var isAttachedPic: Bool { disposition?.attachedPic == 1 }
        var isDolbyVision: Bool {
            sideDataList?.contains { $0.sideDataType == "DOVI configuration record" } ?? false
        }

        /// 회전(display matrix)을 적용한 화면상 크기. ffmpeg는 기본값(autorotate)으로 픽셀을 실제로 돌린다.
        var displaySize: [Int]? {
            guard let width, let height else { return nil }
            let rotation = sideDataList?.compactMap(\.rotation).first ?? 0
            return Int(abs(rotation)) % 180 == 90 ? [height, width] : [width, height]
        }
    }

    struct Disposition: Decodable {
        var attachedPic: Int?
    }

    struct SideData: Decodable {
        var sideDataType: String?
        var rotation: Double?
    }

    struct Format: Decodable {
        var duration: String?
    }

    static func decode(_ data: Data) throws -> Probe {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Probe.self, from: data)
    }

    /// 커버 아트를 제외한 실제 비디오 스트림.
    var videoStreams: [Stream] { streams.filter { $0.codecType == "video" && !$0.isAttachedPic } }

    func count(_ type: String) -> Int { streams.count { $0.codecType == type && !$0.isAttachedPic } }
    var attachedPics: Int { streams.count(where: \.isAttachedPic) }
    var duration: Double? { format.duration.flatMap(Double.init) }
}
