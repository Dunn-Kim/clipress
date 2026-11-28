import MagicClipCore
import Foundation
import Observation
import UniformTypeIdentifiers

/// 압축에 성공하면 원본을 휴지통으로 옮길지(기본 켬). ContentView의 토글이 같은 키를 쓴다.
let trashOriginalKey = "trashOriginal"

/// 끌어다 놓은 파일 목록과 처리 상태.
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

    var pendingCount: Int { items.count(where: \.pending) }
    var finishedCount: Int { items.count { $0.summary != nil } }

    /// (끝난 파일 수 + 지금 인코딩 중인 파일들의 진행률 합) ÷ 전체 파일 수.
    var overallFraction: Double {
        guard !items.isEmpty else { return 0 }
        let current = items.reduce(0.0) { sum, item in
            if case .encoding(let progress) = item.stage { sum + progress.fraction } else { sum }
        }
        return (Double(finishedCount) + current) / Double(items.count)
    }

    /// 대기·처리 중인 항목만 중복으로 본다. 끝난(취소·실패 포함) 파일은 다시 넣어 재시도할 수 있다.
    /// 폴더는 안에 든 영상 파일(하위 폴더 포함)로 펼친다.
    func add(_ urls: [URL]) {
        for url in urls.flatMap(videoFiles) where !items.contains(where: { $0.summary == nil && $0.url == url }) {
            items.append(Item(url: url))
        }
    }

    private func videoFiles(_ url: URL) -> [URL] {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return [url] }
        let files = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.contentTypeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )?.allObjects as? [URL] ?? []
        return files.filter { file in
            guard let type = (try? file.resourceValues(forKeys: [.contentTypeKey]))?.contentType else { return false }
            return videoTypes.contains { type.conforms(to: $0) }
        }.sorted { $0.path < $1.path }
    }

    func start() {
        running = Task {
            // 몇 시간짜리 인코딩 중에 Mac이 유휴 잠자기로 들어가 큐가 멈추지 않게 한다.
            let activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled], reason: "Magic Clip 인코딩"
            )
            defer {
                ProcessInfo.processInfo.endActivity(activity)
                running = nil
            }
            // 빠름 모드의 하드웨어 인코딩은 CPU를 1코어쯤만 써서 두 파일을 함께 돌린다
            // (M3 Pro 실측: 인코딩 2개 동시 = 처리량 1.31배, 한쪽이 탐색·검증이면 남는 코어를 쓴다).
            // SVT-AV1은 혼자서 모든 코어를 쓰므로 하나씩 한다.
            let mode = mode
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<(mode == .fast ? 2 : 1) { group.addTask { await self.work(mode) } }
            }
        }
    }

    private func work(_ mode: Mode) async {
        while !Task.isCancelled, let index = items.firstIndex(where: \.pending) {
            items[index].pending = false
            let (id, url) = (items[index].id, items[index].url)
            let outcome = await compress(url, mode: mode, tools: tools) { stage in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.update(id) { $0.stage = stage } } }
            }
            var summary = outcome.summary
            if case .done = outcome, UserDefaults.standard.object(forKey: trashOriginalKey) as? Bool ?? true {
                let trashed = (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
                summary += trashed ? ", 원본은 휴지통으로" : ", 원본 휴지통 이동 실패"
            }
            update(id) {
                $0.stage = nil
                $0.summary = summary
            }
        }
    }

    func cancel() { running?.cancel() }

    /// 끝난(완료·스킵·실패) 기록을 목록에서 지운다. 파일은 건드리지 않는다.
    func clearFinished() { items.removeAll { $0.summary != nil } }

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
