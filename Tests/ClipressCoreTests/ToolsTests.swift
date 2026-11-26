import Foundation
import Testing
@testable import ClipressCore

/// 줄 콜백이 모두 반환 전에 끝나야 "완료" 뒤에 늦은 진행률이 덮어쓰지 않는다.
@Test func runDeliversEveryLineBeforeReturning() async throws {
    let tools = Tools()
    var lines = 0
    try await tools.run(URL(filePath: "/usr/bin/seq"), ["1", "200000"]) { _ in lines += 1 }
    #expect(lines == 200_000)
    let text = try await tools.run(URL(filePath: "/usr/bin/seq"), ["1", "200000"]).text
    #expect(text.hasSuffix("199999\n200000\n"))
}

@Test func parsesFFmpegProgressBlocks() {
    // ffmpeg -progress 출력: speed는 %4.3gx 형식이라 앞에 공백이 올 수 있고, 처음에는 N/A다.
    let lines = """
        frame=0
        fps=0.00
        out_time_us=N/A
        speed=N/A
        progress=continue
        frame=240
        fps=142.50
        out_time_us=5000000
        speed=   5.9x
        progress=continue
        out_time_us=12000000
        progress=end
        """.split(separator: "\n").map(String.init)
    var progress = EncodeProgress()
    var blocks: [EncodeProgress] = []
    for line in lines where progress.apply(line, duration: 10) { blocks.append(progress) }
    #expect(blocks.count == 3)
    #expect(blocks[0].fraction == 0 && blocks[0].speed == nil && blocks[0].eta == nil)
    // 남은 재생 5초 ÷ 5.9배속
    #expect(blocks[1] == EncodeProgress(fraction: 0.5, fps: 142.5, speed: 5.9, eta: 5 / 5.9))
    #expect(blocks[2].fraction == 1 && blocks[2].eta == 0)  // 길이보다 큰 위치는 1로 자른다
}

@Test func runReportsFailureWithLastErrorLine() async throws {
    await #expect(throws: ToolError.self) {
        try await Tools().run(URL(filePath: "/bin/sh"), ["-c", "echo boom >&2; exit 3"])
    }
}

@Test func parsesFFmpegVersion() throws {
    let release = try #require(ffmpegVersion("ffmpeg version 9.1 Copyright (c) 2000-2026"))
    #expect(release.0 == 9 && release.1 == 1)
    let tagged = try #require(ffmpegVersion("ffmpeg version n8.0.3"))
    #expect(tagged.0 == 8 && tagged.1 == 0)
    #expect(ffmpegVersion("ffmpeg version N-123-gabc") == nil)
}
