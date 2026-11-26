import Foundation

struct ToolError: LocalizedError {
    var errorDescription: String?
}

struct RunResult {
    var out: Data
    var err: String
    var status: Int32
    var text: String { String(decoding: out, as: UTF8.self) }
    var lastErrorLine: String { err.split(separator: "\n").last.map(String.init) ?? "종료 코드 \(status)" }
}

extension Tools {
    /// 도구를 실행하고 stdout·stderr를 EOF까지 읽은 뒤 반환한다. Task 취소 시 SIGINT로 중단한다.
    /// `onLine`을 주면 stdout을 쌓지 않고 줄 단위로 넘긴다. 모든 줄은 반환 전에 전달된다.
    @discardableResult
    func run(
        _ tool: URL, _ args: [String], check: Bool = true, onLine: ((String) -> Void)? = nil
    ) async throws -> RunResult {
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = tool
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        // ab-av1은 ffmpeg/ffprobe를 PATH에서 찾는다.
        env["PATH"] = ffmpeg.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let outChunks = chunks(of: out.fileHandleForReading)
        let errChunks = chunks(of: err.fileHandleForReading)
        let exit = AsyncStream<Int32> { continuation in
            process.terminationHandler = {
                continuation.yield($0.terminationStatus)
                continuation.finish()
            }
        }
        try process.run()

        return try await withTaskCancellationHandler {
            async let errTail = tail(of: errChunks)
            var outData = Data()
            for await chunk in outChunks {
                outData.append(chunk)
                guard let onLine else { continue }
                var start = outData.startIndex
                while let newline = outData[start...].firstIndex(of: 0x0A) {
                    onLine(String(decoding: outData[start..<newline], as: UTF8.self))
                    start = newline + 1
                }
                outData.removeSubrange(..<start)
            }
            if let onLine, !outData.isEmpty { onLine(String(decoding: outData, as: UTF8.self)) }
            var status: Int32 = -1
            for await code in exit { status = code }
            let result = RunResult(out: onLine == nil ? outData : Data(), err: await errTail, status: status)
            try Task.checkCancellation()
            if check, status != 0 {
                throw ToolError(errorDescription: "\(tool.lastPathComponent): \(result.lastErrorLine)")
            }
            return result
        } onCancel: {
            guard process.isRunning else { return }
            // 자식(ab-av1이 띄운 ffmpeg)까지 멈추도록 프로세스 그룹에 보낸다.
            let pid = process.processIdentifier
            if getpgid(pid) == pid { kill(-pid, SIGINT) } else { process.interrupt() }
        }
    }
}

/// 파이프마다 독립된 readabilityHandler로 읽고 EOF(빈 Data)에서 끝낸다.
/// `FileHandle.bytes`는 여러 파이프의 읽기를 직렬로 처리해, stderr를 기다리는 동안 stdout이 가득 차 교착된다(실측).
private func chunks(of handle: FileHandle) -> AsyncStream<Data> {
    AsyncStream { continuation in
        handle.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
    }
}

/// 몇 시간짜리 진행 표시가 쌓이지 않도록 끝부분만 남긴다.
private func tail(of chunks: AsyncStream<Data>) async -> String {
    var data = Data()
    for await chunk in chunks {
        data.append(chunk)
        if data.count > 16_384 { data = data.suffix(8_192) }
    }
    return String(decoding: data, as: UTF8.self)
}
