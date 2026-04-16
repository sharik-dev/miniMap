import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [
                .nonactivatingPanel,
                .borderless,
                .fullSizeContentView
            ],
            backing: .buffered,
            defer: false
        )

        self.level = .screenSaver
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.animationBehavior = .none

        // Auto-save window position
        let windowName = NSWindow.FrameAutosaveName("SpaceMapPanel")
        self.setFrameAutosaveName(windowName)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

func makeFloatingPanel(manager: SpacesManager) -> FloatingPanel {
    let barHeight: CGFloat = 50
    let barWidth: CGFloat = 600

    let screen = NSScreen.main ?? NSScreen.screens[0]
    let x = (screen.visibleFrame.width - barWidth) / 2 + screen.visibleFrame.minX
    let y = screen.visibleFrame.minY + 20

    let panel = FloatingPanel(
        contentRect: NSRect(x: x, y: y, width: barWidth, height: barHeight)
    )

    let rootView = ContentView()
        .environment(manager)

    let hostingView = NSHostingView(rootView: rootView)
    hostingView.autoresizingMask = [.width, .height]

    panel.contentView = hostingView
    return panel
}
