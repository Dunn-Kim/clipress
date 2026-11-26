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

            List(queue.items) { item in
                HStack {
                    Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(item.status).foregroundStyle(.secondary).lineLimit(1)
                }
                .help(item.status)  // 한 줄에서 잘린 실패 메시지 전체를 본다.
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
