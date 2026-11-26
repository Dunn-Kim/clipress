import Foundation

/// `ffprobe -show_format -show_streams -of json` 결과 중 clipress가 쓰는 부분.
public struct Probe: Decodable, Sendable {
    public var streams: [Stream]
    public var format: Format

    public struct Stream: Decodable, Sendable {
        public var index: Int
        public var codecType: String?
        public var width: Int?
        public var height: Int?
        public var avgFrameRate: String?
        public var colorTransfer: String?
        public var disposition: Disposition?
        public var sideDataList: [SideData]?

        public var isAttachedPic: Bool { disposition?.attachedPic == 1 }
        public var isDolbyVision: Bool {
            sideDataList?.contains { $0.sideDataType == "DOVI configuration record" } ?? false
        }

        /// 회전(display matrix)을 적용한 화면상 크기. ffmpeg는 기본값(autorotate)으로 픽셀을 실제로 돌린다.
        public var displaySize: [Int]? {
            guard let width, let height else { return nil }
            let rotation = sideDataList?.compactMap(\.rotation).first ?? 0
            return Int(abs(rotation)) % 180 == 90 ? [height, width] : [width, height]
        }
    }

    public struct Disposition: Decodable, Sendable {
        public var attachedPic: Int?
    }

    public struct SideData: Decodable, Sendable {
        public var sideDataType: String?
        public var rotation: Double?
    }

    public struct Format: Decodable, Sendable {
        public var duration: String?
        public var size: String?
    }

    public static func decode(_ data: Data) throws -> Probe {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Probe.self, from: data)
    }

    /// 커버 아트를 제외한 실제 비디오 스트림.
    public var videoStreams: [Stream] { streams.filter { $0.codecType == "video" && !$0.isAttachedPic } }

    public func count(_ type: String) -> Int { streams.count { $0.codecType == type && !$0.isAttachedPic } }
    public var attachedPics: Int { streams.count(where: \.isAttachedPic) }
    public var duration: Double? { format.duration.flatMap(Double.init) }
}
