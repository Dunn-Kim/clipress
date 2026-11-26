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
