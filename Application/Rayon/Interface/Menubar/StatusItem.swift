//
//  StatusItem.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/1.
//

import AppKit
import MachineStatus
import MachineStatusView
import NSRemoteShell
import RayonModule
import SwiftUI

class MenubarStatusItem: NSObject, Identifiable, ObservableObject {
    let id: UUID = .init()

    let machine: RDMachine
    let identity: RDIdentity
    var eventMonitor: EventMonitor?
    var popover: NSPopover
    var statusInfo: ServerStatus = .init()

    var loopContinue: Bool = true

    var representedShell: NSRemoteShell?

    // Reader Mode State
    @Published var isReaderModeEnabled: Bool = false

    init(machine: RDMachine, identity: RDIdentity) {
        self.machine = machine
        self.identity = identity

        let buildPopover = NSPopover()
        popover = buildPopover

        super.init()

        let contentView = ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(machine.name)
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    // Reader Mode button
                    ReaderModeButton(isEnabled: isReaderModeEnabled) {
                        self.toggleReaderMode()
                    }
                    // Close button
                    CloseButton {
                        self.closeThisItem()
                    }
                }
                Divider()
                ServerStatusViews
                    .createBaseStatusView(withContext: statusInfo)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .contentShape(Rectangle())
            .buttonStyle(PlainButtonStyle())
            .textSelection(.enabled)
            .padding(.top, 10)
            .padding(.horizontal, 15)
            .padding(.bottom, 15)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .contentShape(Rectangle())
        .buttonStyle(PlainButtonStyle())
        .frame(width: 350, height: 700)

        let hostingController = NSHostingController(rootView: contentView)
        buildPopover.contentViewController = hostingController
        buildPopover.behavior = .transient
        buildPopover.animates = false

        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown], handler: mouseEventHandler)

        beginShellLoop()
        beginFrameLoop()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(sender:))
    }

    deinit {
        debugPrint("\(self) \(#function)")
    }

    let accessLock = NSLock()

    let statusItem: NSStatusItem = NSStatusBar
        .system
        .statusItem(withLength: NSStatusItem.variableLength)

    let frames: [NSImage] = {
        [
            NSImage(named: "cat_frame_0"),
            NSImage(named: "cat_frame_1"),
            NSImage(named: "cat_frame_2"),
            NSImage(named: "cat_frame_3"),
            NSImage(named: "cat_frame_4"),
        ]
        .compactMap { $0 }
    }()

    var currentImageIndex: Int = 0
    enum CatSpeed: TimeInterval {
        case light = 0.05
        case fast = 0.1
        case run = 0.25
        case walk = 0.5
        case hang = 1
        case broken = -1
    }

    var catSpeed = CatSpeed.broken

    @objc func togglePopover(sender: AnyObject) {
        if popover.isShown {
            hidePopover(sender)
        } else {
            showPopover(sender)
        }
    }

    func showPopover(_: AnyObject) {
        if let statusBarButton = statusItem.button {
            popover.show(relativeTo: statusBarButton.bounds, of: statusBarButton, preferredEdge: NSRectEdge.maxY)
            eventMonitor?.start()
        }
    }

    func hidePopover(_ sender: AnyObject) {
        popover.performClose(sender)
        eventMonitor?.stop()
    }

    func mouseEventHandler(_ event: NSEvent?) {
        if popover.isShown, let event = event {
            hidePopover(event)
        }
    }

    func closeThisItem() {
        popover.close()
        let shell = representedShell
        representedShell = nil
        DispatchQueue.global().async {
            shell?.requestDisconnectAndWait()
            shell?.destroyPermanently()
        }
        loopContinue = false
        eventMonitor = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        MenubarTool.shared.remove(menubarItem: id)
    }

    // MARK: - Reader Mode

    func toggleReaderMode() {
        isReaderModeEnabled.toggle()
        // Reader mode provides button hover effects - no additional implementation needed
    }
}

// MARK: - Reader Mode Button Component

struct ReaderModeButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Image(systemName: "book")
            .font(.system(size: 14, weight: .regular, design: .rounded))
            .foregroundColor(isEnabled ? .blue : .gray)
            .frame(width: 24, height: 24)
            .onTapGesture {
                action()
            }
    }
}

// MARK: - Close Button Component

struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Circle()
            .foregroundColor(.gray.opacity(0.5))
            .overlay(
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            )
            .frame(width: 20, height: 20)
            .onTapGesture {
                action()
            }
    }
}
