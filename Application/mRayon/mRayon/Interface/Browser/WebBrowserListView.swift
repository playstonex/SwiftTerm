//
//  WebBrowserListView.swift
//  mRayon
//
//  Created for GoodTerm Browser Feature
//

import RayonModule
import SwiftUI

struct WebBrowserListView: View {
    @EnvironmentObject var store: RayonStore
    @StateObject var browserManager = WebBrowserManager.shared

    @State var openEditView: Bool = false
    @State var searchKey: String = ""

    var content: [RDBrowserSession.ID] {
        if searchKey.isEmpty {
            return store.browserSessionGroup.sessions.map(\.id)
        }
        let searchText = searchKey.lowercased()
        return store
            .browserSessionGroup
            .sessions
            .filter { object in
                if object.name.lowercased().contains(searchText) {
                    return true
                }
                if object.remoteHost.lowercased().contains(searchText) {
                    return true
                }
                if String(object.remotePort).contains(searchText) {
                    return true
                }
                if let machineName = object.getMachineName(),
                   machineName.lowercased().contains(searchText) {
                    return true
                }
                return false
            }
            .map(\.id)
    }

    var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 280, maximum: 500), spacing: 10)]
    }

    var body: some View {
        Group {
            if store.browserSessionGroup.sessions.isEmpty {
                PlaceholderView("No Browser Sessions", img: .connectionBroken)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("\(content.count) browser session(s) available, tap for options.", systemImage: "globe")
                            .font(.system(.footnote, design: .rounded))
                        Divider()
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                            ForEach(content, id: \.self) { sessionId in
                                WebBrowserSessionElementView(sessionId: sessionId)
                            }
                        }
                        Divider()
                        Label("EOF", systemImage: "text.append")
                            .font(.system(.footnote, design: .rounded))
                    }
                    .padding()
                }
                .searchable(text: $searchKey)
            }
        }
        .animation(.interactiveSpring(), value: content)
        .animation(.interactiveSpring(), value: searchKey)
        .navigationDestination(isPresented: $openEditView) {
            EditBrowserSessionView()
        }
        .navigationTitle("Web Browser")
        .toolbar {
            ToolbarItem {
                Button {
                    openEditView = true
                } label: {
                    Label("Create Session", systemImage: "plus")
                }
            }
        }
    }

}

// MARK: - Session Element View

struct WebBrowserSessionElementView: View {
    @EnvironmentObject var store: RayonStore
    @StateObject var browserManager = WebBrowserManager.shared

    @State var sessionId: RDBrowserSession.ID
    @State var openEdit: Bool = false
    @State var openBrowser: Bool = false

    var session: RDBrowserSession {
        store.browserSessionGroup[sessionId]
    }

    var isRunning: Bool {
        browserManager.isRunning(sessionId: sessionId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: "globe")
                HStack {
                    Text(session.name.isEmpty ? "Browser Session" : session.name)
                    Spacer()
                    Text(isRunning ? "RUNNING" : "IDLE")
                        .font(.caption)
                        .foregroundColor(isRunning ? .green : .secondary)
                }
            }
            .font(.system(.headline, design: .rounded))

            Divider()

            HStack(spacing: 4) {
                VStack(alignment: .trailing, spacing: 5) {
                    Text("Machine:")
                        .lineLimit(1)
                    Text("Target:")
                        .lineLimit(1)
                    Text("Port:")
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.getMachineName() ?? "Not Set")
                        .lineLimit(1)
                    Text(session.remoteHost)
                        .lineLimit(1)
                    Text(String(session.remotePort))
                        .lineLimit(1)
                }
            }
            .font(.system(.subheadline, design: .rounded))

            Divider()

            Text(sessionId.uuidString)
                .textSelection(.enabled)
                .font(.system(size: 8, weight: .light, design: .monospaced))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            Color(
                isRunning ?
                    UIColor.systemBlue.withAlphaComponent(0.1)
                    : UIColor.systemGray6
            )
            .roundedCorner()
        )
        .overlay {
            Menu {
                Section {
                    if isRunning {
                        Button {
                            browserManager.end(for: sessionId)
                        } label: {
                            Label("Disconnect", systemImage: "xmark.circle")
                        }

                        if let context = browserManager.browser(for: sessionId) {
                            NavigationLink {
                                WebBrowserView(context: context)
                            } label: {
                                Label("Open Browser", systemImage: "safari")
                            }
                        }
                    } else {
                        Button {
                            startBrowserSession()
                        } label: {
                            Label("Connect & Open", systemImage: "play.circle")
                        }
                    }
                }

                if !isRunning {
                    Section {
                        Button {
                            openEdit = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button {
                            var newSession = session
                            newSession.id = .init()
                            store.browserSessionGroup.insert(newSession)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                    }

                    Section {
                        Button {
                            UIBridge.requiresConfirmation(
                                message: "Are you sure you want to delete this browser session?"
                            ) { confirmed in
                                if confirmed {
                                    store.browserSessionGroup.delete(sessionId)
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } label: {
                Color.accentColor
                    .opacity(0.0001)
            }
            .offset(x: 0, y: 4)
        }
        .navigationDestination(isPresented: $openEdit) {
            EditBrowserSessionView { sessionId }
        }
    }

    func startBrowserSession() {
        guard session.isValid() else {
            UIBridge.presentError(with: "Invalid browser session configuration")
            return
        }
        guard browserManager.begin(for: session) != nil else {
            return
        }
        // Navigate to browser view after connection starts
        openBrowser = true
    }
}

// MARK: - Preview

struct WebBrowserListView_Previews: PreviewProvider {
    static func getView() -> some View {
        var session = RDBrowserSession(
            name: "Test Server",
            remoteHost: "127.0.0.1",
            remotePort: 3000
        )
        session.id = UUID(uuidString: "587A88BF-823C-46D6-AFA7-987045026EEC")!
        RayonStore.shared.browserSessionGroup.insert(session)
        return WebBrowserListView()
    }

    static var previews: some View {
        createPreview {
            AnyView(getView())
        }
    }
}
