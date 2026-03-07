//
//  WebBrowserManager.swift
//  mRayon
//
//  Created for GoodTerm Browser Feature
//

import Combine
import Foundation
import RayonModule
import SwiftUI

class WebBrowserManager: ObservableObject {
    static let shared = WebBrowserManager()

    private init() {}

    @Published var browsers: [WebBrowserContext] = []

    var usedLocalPorts: Set<Int> {
        Set(browsers.map { $0.localPort }.filter { $0 > 0 })
    }

    @MainActor
    func begin(for session: RDBrowserSession) -> WebBrowserContext? {
        // Check if session already has a running browser
        if let existing = browsers.first(where: { $0.id == session.id }) {
            return existing
        }

        guard session.isValid() else {
            UIBridge.presentError(with: "Invalid browser session configuration")
            return nil
        }

        let context = WebBrowserContext(session: session)
        browsers.append(context)

        // Start connection in background
        context.connectAndForward()

        UIBridge.presentSuccess(with: "Browser session started")
        return context
    }

    @MainActor
    func end(for sessionId: UUID) {
        guard let index = browsers.firstIndex(where: { $0.id == sessionId }) else {
            return
        }

        let context = browsers.remove(at: index)
        context.disconnect()
    }

    @MainActor
    func endAll() {
        for context in browsers {
            context.disconnect()
        }
        browsers.removeAll()
    }

    func browser(for sessionId: UUID) -> WebBrowserContext? {
        browsers.first(where: { $0.id == sessionId })
    }

    func isRunning(sessionId: UUID) -> Bool {
        browsers.contains(where: { $0.id == sessionId })
    }
}
