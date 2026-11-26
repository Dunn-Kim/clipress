import ClipressCore
import SwiftUI

struct ContentView: View {
    @State private var queue = Queue()
    @State private var showLossNote = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let problem = queue.toolProblem {
                Text(problem).foregroundStyle(.red)
            }
            HStack {
                Picker("모드", selection: $queue.mode) {
                    Text("빠름 (HEVC 하드웨어)").tag(Mode.fast)
                    Text("고압축 (AV1)").tag(Mode.max)
                }
                .pickerStyle(.segmented)
                .disabled(queue.running != nil)
                // .help() 툴팁은 이 앱에서 표시되지 않아(실사용 확인) 마우스를 올리거나 누르면 팝오버로 보여 준다.
                Button { showLossNote.toggle() } label: {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .onHover { showLossNote = $0 }
                .popover(isPresented: $showLossNote, arrowEdge: .bottom) {
                    Text(queue.mode.lossNote)
                        .font(.system(size: 14))
                        .frame(width: 380, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                }
                .accessibilityLabel("변환 손실 안내")
            }

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
            HStack(alignment: .firstTextBaseline) {
                Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Spacer()
                // 툴팁 대신 두 줄까지 보여 줘서 긴 실패 메시지도 읽을 수 있게 한다.
                Text(status)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 360, alignment: .trailing)
            }

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

private extension Mode {
    /// 변환으로 생기는 손실. 두 모드 공통: 손실 압축 재인코딩이며 목표는 샘플 평균 VMAF 96이다.
    var lossNote: String {
        switch self {
        case .fast:
            """
            HEVC 하드웨어(VideoToolbox) 변환 시 손실
            • 손실 압축 재인코딩: 목표 VMAF 96(샘플 평균)이라 대부분 구분하기 어렵지만, 어두운 장면의 밴딩, 필름 입자·미세한 질감이 뭉개질 수 있습니다.
            • 하드웨어 인코더는 같은 화질에서 소프트웨어보다 파일이 커서, 이미 효율적인 원본은 절감 부족으로 건너뜁니다.
            • 타임코드 등 데이터 스트림은 빠집니다. 오디오·자막·챕터·커버 아트는 그대로입니다.
            """
        case .max:
            """
            AV1(SVT-AV1) 변환 시 손실
            • 손실 압축 재인코딩: 목표 VMAF 96(샘플 평균). AV1은 필름 입자·노이즈를 매끄럽게 만들고 어두운 영역의 디테일을 줄이는 경향이 있습니다.
            • 매우 느립니다. 4K 영화는 몇 시간 걸릴 수 있습니다.
            • M3 이전 Mac과 구형 기기는 AV1 하드웨어 재생을 못 해 QuickTime에서 열리지 않을 수 있습니다.
            • MOV 원본은 MP4로 저장되고, 타임코드 등 데이터 스트림은 빠집니다.
            """
        }
    }
}
