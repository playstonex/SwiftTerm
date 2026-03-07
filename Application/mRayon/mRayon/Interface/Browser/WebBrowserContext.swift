//
//  WebBrowserContext.swift
//  mRayon
//
//  Created for GoodTerm Browser Feature
//

import Combine
import Foundation
import NSRemoteShell
import RayonModule
import SwiftUI
import WebKit

class WebBrowserContext: ObservableObject, Identifiable {
    let id: UUID
    let session: RDBrowserSession
    let machine: RDMachine
    let shell: NSRemoteShell

    @Published var connectionState: ConnectionState = .disconnected
    @Published var localPort: Int = 0
    @Published var errorMessage: String?

    private var webView: WKWebView?

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case authenticating
        case creatingTunnel
        case connected
        case error(String)

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.authenticating, .authenticating),
                 (.creatingTunnel, .creatingTunnel),
                 (.connected, .connected):
                return true
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    var localUrl: URL? {
        guard localPort > 0 else { return nil }
        return URL(string: "http://127.0.0.1:\(localPort)")
    }

    init(session: RDBrowserSession) {
        self.id = session.id
        self.session = session
        self.shell = .init()

        guard let machineId = session.usingMachine,
              let machine = RayonStore.shared.machineGroup[machineId].isNotPlaceholder() ? RayonStore.shared.machineGroup[machineId] : nil
        else {
            self.machine = RDMachine()
            self.connectionState = .error("Invalid machine configuration")
            return
        }
        self.machine = machine
    }

    func allocateLocalPort() -> Int {
        let usedPorts = WebBrowserManager.shared.usedLocalPorts

        // Try common ports for local development
        // Note: We can't use socket bind on iOS due to sandbox restrictions
        // We just avoid ports used by other browser contexts and let NSRemoteShell
        // handle the actual binding
        let preferredPorts = [3000, 3001, 3002, 4000, 5000, 5001, 8000, 8080, 8081, 8888, 9000]
        for port in preferredPorts {
            if !usedPorts.contains(port) {
                print("[WebBrowser] Allocated preferred port \(port)")
                return port
            }
        }

        // Fall back to higher ports
        for port in 10000...65535 {
            if !usedPorts.contains(port) {
                print("[WebBrowser] Allocated fallback port \(port)")
                return port
            }
        }
        print("[WebBrowser] Failed to allocate any port")
        return 0
    }

    func connectAndForward() {
        guard session.isValid() else {
            mainActor {
                self.connectionState = .error("Invalid session configuration")
                self.errorMessage = "Invalid session configuration"
            }
            return
        }

        let port = allocateLocalPort()
        guard port > 0 else {
            mainActor {
                self.connectionState = .error("Failed to allocate local port")
                self.errorMessage = "Failed to allocate local port"
            }
            return
        }

        mainActor {
            self.localPort = port
            self.connectionState = .connecting
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.performConnection(localPort: port)
        }
    }

    private func performConnection(localPort: Int) {
        // Setup connection
        shell
            .setupConnectionHost(machine.remoteAddress)
            .setupConnectionPort(NSNumber(value: Int(machine.remotePort) ?? 22))
            .setupConnectionTimeout(RayonStore.shared.timeoutNumber)
            .requestConnectAndWait()

        let remoteAddress = machine.remoteAddress
        let remotePort = machine.remotePort

        guard shell.isConnected else {
            mainActor {
                self.connectionState = .error("Failed to connect to \(remoteAddress):\(remotePort)")
                self.errorMessage = "Failed to connect to \(remoteAddress):\(remotePort)"
            }
            return
        }

        mainActor {
            self.connectionState = .authenticating
        }

        // Authenticate
        if let identityId = machine.associatedIdentity,
           let uuid = UUID(uuidString: identityId) {
            let identity = RayonStore.shared.identityGroup[uuid]
            guard !identity.username.isEmpty else {
                mainActor {
                    self.connectionState = .error("Invalid identity configuration")
                    self.errorMessage = "Invalid identity configuration"
                }
                return
            }
            identity.callAuthenticationWith(remote: shell)
        } else {
            // Try auto-auth
            for identity in RayonStore.shared.identityGroupForAutoAuth {
                identity.callAuthenticationWith(remote: shell)
                if shell.isAuthenticated {
                    break
                }
            }
        }

        guard shell.isAuthenticated else {
            mainActor {
                self.connectionState = .error("Authentication failed")
                self.errorMessage = "Authentication failed"
            }
            return
        }

        mainActor {
            self.connectionState = .creatingTunnel
        }

        // Create port forward
        shell.createPortForward(
            withLocalPort: NSNumber(value: localPort),
            withForwardTargetHost: session.remoteHost,
            withForwardTargetPort: NSNumber(value: session.remotePort)
        ) { [weak self] in
            mainActor {
                self?.connectionState = .connected
                self?.errorMessage = nil
            }
        } withContinuationHandler: {
            true // Keep tunnel alive
        }
    }

    func disconnect() {
        let cleanup = {
            self.webView?.navigationDelegate = nil
            self.webView?.stopLoading()
            self.webView = nil
            self.connectionState = .disconnected
            self.localPort = 0
        }
        
        if Thread.isMainThread {
            cleanup()
        } else {
            DispatchQueue.main.async(execute: cleanup)
        }

        // Disconnect shell on background thread safely
        DispatchQueue.global().async {
            self.shell.requestDisconnectAndWait()
            self.shell.destroyPermanently()
            
            // Release context on main thread to avoid ObservableObject/SwiftUI dealloc crashes
            DispatchQueue.main.async {
                _ = self
            }
        }
    }

    func getWebView() -> WKWebView {
        if let existing = webView {
            return existing
        }

        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        // Don't set navigationDelegate here - let WebViewRepresentable's coordinator handle it
        self.webView = webView

        return webView
    }

    func load(url: URL) {
        let webView = getWebView()
        webView.load(URLRequest(url: url))
    }

    func loadInitialPage() {
        guard let url = localUrl else { return }

        // If we have a last URL that starts with the local base, use it
        if let lastUrl = session.lastUrl,
           let lastUrlObj = URL(string: lastUrl),
           lastUrl.hasPrefix("http://127.0.0.1:\(localPort)") || lastUrl.hasPrefix("http://localhost:\(localPort)") {
            load(url: lastUrlObj)
        } else {
            load(url: url)
        }
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func refresh() {
        webView?.reload()
    }

    var currentUrl: String? {
        webView?.url?.absoluteString
    }

    var canGoBack: Bool {
        webView?.canGoBack ?? false
    }

    var canGoForward: Bool {
        webView?.canGoForward ?? false
    }

    var isLoading: Bool {
        webView?.isLoading ?? false
    }

    func updateSessionLastUrl() {
        guard let url = currentUrl else { return }
        var updatedSession = session
        updatedSession.lastUrl = url
        RayonStore.shared.browserSessionGroup.insert(updatedSession)
    }
}
