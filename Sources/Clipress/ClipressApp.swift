import AppKit
import ClipressCore
import SwiftUI

@main
struct ClipressApp: App {
    // .app 번들 없이 `swift run`으로 띄워도 Dock 아이콘과 키보드 포커스를 갖도록 한다.
    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        Window("Clipress", id: "main") { ContentView() }
    }
}

@MainActor @Observable
final class Queue {
    struct Item: Identifiable {
        let id = UUID()
        let url: URL
        var pending = true
        var status = "대기"
    }

    var items: [Item] = []
    var mode: Mode = .fast
    var toolProblem: String?
    var running: Task<Void, Never>?
    let tools = Tools()

    func add(_ urls: [URL]) {
        items += urls.filter { url in !items.contains { $0.url == url } }.map { Item(url: $0) }
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
                let outcome = await compress(items[index].url, mode: mode, tools: tools) { status in
                    DispatchQueue.main.async { MainActor.assumeIsolated { self.setStatus(id, status) } }
                }
                setStatus(id, Self.describe(outcome))
            }
        }
    }

    func cancel() { running?.cancel() }

    private func setStatus(_ id: UUID, _ status: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
    }

    static func describe(_ outcome: Outcome) -> String {
        switch outcome {
        case .done(let before, let after, let note):
            let saved = Int((1 - Double(after) / Double(before)) * 100)
            let sizes = "\(before.formatted(.byteCount(style: .file))) → \(after.formatted(.byteCount(style: .file)))"
            return "완료 −\(saved)% (\(sizes))" + (note.map { ", \($0)" } ?? "")
        case .skipped(let reason): return "스킵: \(reason)"
        case .failed(let reason): return "실패: \(reason)"
        }
    }
}

struct ContentView: View {
    @State private var queue = Queue()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let problem = queue.toolProblem {
                Text(problem).foregroundStyle(.red)
            }
            Picker("모드", selection: $queue.mode) {
                Text("빠름 (HEVC 하드웨어)").tag(Mode.fast)
                Text("고압축 (AV1)").tag(Mode.max)
            }
            .pickerStyle(.segmented)
            .disabled(queue.running != nil)

            List(queue.items) { item in
                HStack {
                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(item.status).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .overlay {
                if queue.items.isEmpty {
                    Text("영상 파일을 여기에 끌어다 놓으세요").foregroundStyle(.secondary)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                queue.add(urls)
                return true
            }

            HStack {
                Text("원본은 그대로 두고 옆에 이름.clipress.확장자로 저장합니다.")
                    .foregroundStyle(.secondary)
                Spacer()
                if queue.running == nil {
                    Button("시작") { queue.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(queue.toolProblem != nil || !queue.items.contains(where: \.pending))
                } else {
                    Button("취소") { queue.cancel() }
                }
            }
        }
        .font(.system(size: 14))  // 한글 본문 가독성
        .padding()
        .frame(minWidth: 560, minHeight: 360)
        .task { queue.toolProblem = await queue.tools.problem() }
    }
}
