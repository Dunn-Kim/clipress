import AppKit
import SwiftUI

@main
struct ClipressApp: App {
    // .app 번들 없이 `swift run`으로 띄워도 Dock 아이콘과 키보드 포커스를 갖도록 한다.
    init() { NSApplication.shared.setActivationPolicy(.regular) }

    var body: some Scene {
        Window("Clipress", id: "main") { ContentView() }
    }
}
