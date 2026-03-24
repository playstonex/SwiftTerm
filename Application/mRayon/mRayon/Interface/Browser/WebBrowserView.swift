//
//  WebBrowserView.swift
//  mRayon
//
//  Created for GoodTerm Browser Feature
//

import RayonModule
import SwiftUI
import WebKit

struct WebBrowserView: View {
    @ObservedObject var context: WebBrowserContext
    @Environment(\.presentationMode) var presentationMode

    @State private var urlText: String = ""
    @State private var isLoading: Bool = false
    @State private var estimatedProgress: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            statusBar

            // URL bar
            urlBar

            // Web view container
            webViewContainer
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    context.disconnect()
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Label(String(localized: "Disconnect"), systemImage: "xmark.circle")
                }
            }
        }
        .onAppear {
            setupWebView()
        }
        .onDisappear {
            context.updateSessionLastUrl()
        }
    }

    private var navigationTitle: String {
        let portInfo = context.localPort > 0
            ? String(format: String(localized: "localhost:%lld"), locale: Locale.current, Int64(context.localPort))
            : String(localized: "connecting...")
        if context.session.name.isEmpty {
            return portInfo
        }
        return String(format: String(localized: "%@ - %@"), locale: Locale.current, context.session.name, portInfo)
    }

    var statusBar: some View {
        Group {
            switch context.connectionState {
            case .disconnected:
                HStack {
                    Image(systemName: "circle.dashed")
                    Text(String(localized: "Disconnected"))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.2))
            case .connecting:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(
                        String(
                            format: String(localized: "Connecting to %@..."),
                            locale: Locale.current,
                            context.machine.remoteAddress
                        )
                    )
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.2))
            case .authenticating:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(String(localized: "Authenticating..."))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.2))
            case .creatingTunnel:
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(
                        String(
                            format: String(localized: "Creating tunnel to %@:%lld..."),
                            locale: Locale.current,
                            context.session.remoteHost,
                            Int64(context.session.remotePort)
                        )
                    )
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.purple.opacity(0.2))
            case .connected:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(
                        String(
                            format: String(localized: "Connected: localhost:%lld → %@:%lld"),
                            locale: Locale.current,
                            Int64(context.localPort),
                            context.session.remoteHost,
                            Int64(context.session.remotePort)
                        )
                    )
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.15))
            case .error(let message):
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .foregroundColor(.red)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.15))
            }
        }
        .font(.caption)
    }

    var urlBar: some View {
        HStack(spacing: 8) {
            // Navigation buttons
            Button {
                context.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(context.canGoBack ? .accentColor : .gray)
            }
            .disabled(!context.canGoBack)

            Button {
                context.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(context.canGoForward ? .accentColor : .gray)
            }
            .disabled(!context.canGoForward)

            Button {
                context.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.accentColor)
            }

            // URL field
            TextField(String(localized: "URL"), text: $urlText)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .keyboardType(.URL)
                .onSubmit {
                    loadUrl()
                }

            Button {
                loadUrl()
            } label: {
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemBackground))
    }

    var webViewContainer: some View {
        ZStack {
            if context.connectionState == .connected {
                WebViewRepresentable(
                    webView: context.getWebView(),
                    isLoading: $isLoading,
                    estimatedProgress: $estimatedProgress,
                    urlText: $urlText
                )
                .edgesIgnoringSafeArea(.all)

                if isLoading {
                    VStack {
                        ProgressView(value: estimatedProgress, total: 1.0)
                            .progressViewStyle(LinearProgressViewStyle())
                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 20) {
                    if case .error(let message) = context.connectionState {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.red)
                        Text(String(localized: "Connection Failed"))
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button(String(localized: "Retry")) {
                            context.connectAndForward()
                        }
                        .buttonStyle(.bordered)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text(String(localized: "Connecting..."))
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemBackground))
            }
        }
    }

    private func setupWebView() {
        if context.connectionState == .disconnected ||
           context.connectionState == .error("") {
            context.connectAndForward()
        }
    }

    private func loadUrl() {
        guard !urlText.isEmpty else { return }

        var urlString = urlText
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "http://\(urlString)"
        }

        // Only allow localhost URLs
        guard let url = URL(string: urlString),
              let host = url.host,
              (host == "127.0.0.1" || host == "localhost") else {
            UIBridge.presentError(with: String(localized: "Only localhost URLs are allowed"))
            return
        }

        context.load(url: url)
    }
}

// MARK: - WebView Representable

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView
    @Binding var isLoading: Bool
    @Binding var estimatedProgress: Double
    @Binding var urlText: String

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Updates are handled by the coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
                self.parent.estimatedProgress = 1.0
                if let url = webView.url {
                    self.parent.urlText = url.absoluteString
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: Error) {
            DispatchQueue.main.async {
                self.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
