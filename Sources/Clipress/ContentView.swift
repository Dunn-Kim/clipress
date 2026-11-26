import ClipressCore
import SwiftUI

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

            List(queue.items) { ItemRow(item: $0) }
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
                Text("원본은 그대로 두고 옆에 이름-pressed.확장자로 저장합니다.")
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
        .frame(minWidth: 600, minHeight: 380)
        .task { queue.toolProblem = await queue.tools.problem() }
    }
}

private struct ItemRow: View {
    let item: Queue.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(status).foregroundStyle(.secondary).lineLimit(1)
            }
            .help(status)  // 한 줄에서 잘린 실패 메시지 전체를 본다.

            if let stage = item.stage {
                HStack(spacing: 10) {
                    if case .encoding(let progress) = stage {
                        ProgressView(value: progress.fraction)
                        SpeedMeter(progress: progress)
                    } else {
                        ProgressView().progressViewStyle(.linear)  // 끝을 알 수 없는 단계
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var status: String {
        switch item.stage {
        case .analyzing: "분석 중"
        case .searching: "품질 탐색 중"
        case .encoding(let progress): "인코딩 \(Int(progress.fraction * 100))%"
        case .verifying: "검증 중"
        case nil: item.summary ?? "대기"
        }
    }
}

/// 인코딩 속도계: 초당 프레임 수, 실시간 대비 배속, 남은 시간.
private struct SpeedMeter: View {
    let progress: EncodeProgress

    var body: some View {
        Label {
            Text([
                progress.fps.map { "\(Int($0.rounded())) fps" },
                progress.speed.map { String(format: "%.1f×", $0) },
                progress.eta.map { "약 \(remaining($0)) 남음" },
            ].compactMap { $0 }.joined(separator: " · "))
                .monospacedDigit()
        } icon: {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    /// 1시간 미만은 "4:05", 이상은 "1:04:05".
    private func remaining(_ seconds: Double) -> String {
        let duration = Duration.seconds(seconds.rounded())
        return duration.formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }
}
