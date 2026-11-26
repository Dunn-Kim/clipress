import ClipressCore
import Foundation
import Observation

/// 끌어다 놓은 파일 목록과 순차 처리 상태.
@MainActor @Observable
final class Queue {
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        var pending = true
        /// 처리 중일 때의 단계. 끝나면 nil.
        var stage: Stage?
        /// 끝난 뒤의 결과 요약.
        var summary: String?
    }

    var items: [Item] = []
    var mode: Mode = .fast
    var toolProblem: String?
    var running: Task<Void, Never>?
    let tools = Tools()

    /// 대기 중인 항목만 중복으로 본다. 끝난(취소·실패 포함) 파일은 다시 넣어 재시도할 수 있다.
    func add(_ urls: [URL]) {
        items += urls.filter { url in !items.contains { $0.pending && $0.url == url } }.map { Item(url: $0) }
    }

    func start() {
        running = Task {
            // 몇 시간짜리 인코딩 중에 Mac이 유휴 잠자기로 들어가 큐가 멈추지 않게 한다.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: "Clipress 인코딩"
            )
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                running = nil
            }
            while !Task.isCancelled, let index = items.firstIndex(where: \.pending) {
                items[index].pending = false
                let id = items[index].id
                let outcome = await compress(items[index].url, mode: mode, tools: tools) { stage in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.update(id) { $0.stage = stage } } }
                }
                update(id) {
                    $0.stage = nil
                    $0.summary = outcome.summary
                }
            }
        }
    }

    func cancel() { running?.cancel() }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }
}

private extension Outcome {
    var summary: String {
        switch self {
        case .done(let before, let after, let note):
            let saved = 100 - Int((Double(after) / Double(before) * 100).rounded())
            let sizes = "\(before.formatted(.byteCount(style: .file))) → \(after.formatted(.byteCount(style: .file)))"
            return "완료 −\(saved)% (\(sizes))" + (note.map { ", \($0)" } ?? "")
        case .skipped(let reason): return "스킵: \(reason)"
        case .failed(let reason): return "실패: \(reason)"
        }
    }
}
