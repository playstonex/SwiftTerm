//
//  SettingWindow.swift
//  Rayon (macOS)
//
//  Created for GoodTerm
//

import RayonModule
import SettingsUI
import SwiftUI

class SettingWindow: NSWindow {
    static let shared = SettingWindow()

    private init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        // Create view with store
        let view = SettingWindowView()
            .environmentObject(RayonStore.shared)

        // Create hosting view with Any type
        let hostingView = NSHostingView(rootView: view)
        contentView = hostingView

        // Setup window
        title = "Settings"
        center()

        // Set window background color
        backgroundColor = NSColor.windowBackgroundColor

        // Show window
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingWindowView: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        SettingsViewContainer()
            .environmentObject(store)
            .frame(minWidth: 900, minHeight: 600)
    }
}
