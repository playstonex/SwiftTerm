//
//  Generic.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/11.
//

import Foundation
import RayonModule
import SwiftUI

enum RayonUtil {
    static func findWindow() -> NSWindow? {
        if let key = NSApp.keyWindow {
            return key
        }
        for window in NSApp.windows where window.isVisible {
            return window
        }
        return nil
    }

    static func selectIdentity() async -> RDIdentity.ID? {
        debugPrint("Picking Identity")

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                var panelRef: NSPanel?
                var windowRef: NSWindow?
                let controller = NSHostingController(rootView: Group {
                    IdentityPickerSheetView {
                        if let panel = panelRef {
                            if let windowRef = windowRef {
                                windowRef.endSheet(panel)
                            } else {
                                panel.close()
                            }
                        }
                        continuation.resume(returning: $0)
                    }
                    .environmentObject(RayonStore.shared)
                    .frame(width: 700, height: 400)
                })
                let panel = NSPanel(contentViewController: controller)
                panelRef = panel
                panel.title = ""
                panel.titleVisibility = .hidden

                if let keyWindow = findWindow() {
                    windowRef = keyWindow
                    keyWindow.beginSheet(panel) { _ in }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    static func selectMachine(allowMany: Bool = true) async -> [RDMachine.ID] {
        debugPrint("Picking Machine")

        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                var panelRef: NSPanel?
                var windowRef: NSWindow?
                let controller = NSHostingController(rootView: Group {
                    MachinePickerView(onComplete: {
                        if let panel = panelRef {
                            if let windowRef = windowRef {
                                windowRef.endSheet(panel)
                            } else {
                                panel.close()
                            }
                        }
                        continuation.resume(returning: $0)
                    }, allowSelectMany: allowMany)
                        .environmentObject(RayonStore.shared)
                        .frame(width: 700, height: 400)
                })
                let panel = NSPanel(contentViewController: controller)
                panelRef = panel
                panel.title = ""
                panel.titleVisibility = .hidden

                if let keyWindow = findWindow() {
                    windowRef = keyWindow
                    keyWindow.beginSheet(panel) { _ in }
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    static func selectOneMachine() async -> RDMachine.ID? {
        await selectMachine(allowMany: false).first
    }
}

extension String {
    var isValidAsFilename: Bool {
        var invalidCharacters = CharacterSet(charactersIn: ":/")
        invalidCharacters.formUnion(.newlines)
        invalidCharacters.formUnion(.illegalCharacters)
        invalidCharacters.formUnion(.controlCharacters)
        return rangeOfCharacter(from: invalidCharacters) == nil && !isEmpty
    }
}
