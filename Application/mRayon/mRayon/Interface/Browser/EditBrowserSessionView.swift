//
//  EditBrowserSessionView.swift
//  mRayon
//
//  Created for GoodTerm Browser Feature
//

import RayonModule
import SwiftUI

struct EditBrowserSessionView: View {
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var store: RayonStore

    let inEditWith: (() -> (UUID?))?

    init(requestIdentity: (() -> (UUID?))? = nil) {
        inEditWith = requestIdentity
    }

    @State var initializedOnce = false

    @State var name: String = ""
    @State var remoteHost: String = "127.0.0.1"
    @State var remotePort: Int = 3000
    @State var usingMachine: RDMachine.ID? = nil

    var generateObject: RDBrowserSession {
        RDBrowserSession(
            name: name,
            usingMachine: usingMachine,
            remoteHost: remoteHost,
            remotePort: remotePort
        )
    }

    var sessionDescription: String {
        generateObject.shortDescription()
    }

    var body: some View {
        List {
            Section {
                TextField("Name (optional)", text: $name)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
            } header: {
                Label("Session Name", systemImage: "tag")
            } footer: {
                Text("A friendly name for this browser session")
            }

            Section {
                TextField("Target Address", text: $remoteHost)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                TextField("Target Port", text: .init(get: {
                    String(remotePort)
                }, set: { str in
                    remotePort = Int(str) ?? 0
                }))
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .keyboardType(.numberPad)
            } header: {
                Label("Target Host", systemImage: "network")
            } footer: {
                Text("The remote host and port to tunnel to (e.g., Next.js dev server on localhost:3000)")
            }

            Section {
                Button {
                    Task {
                        usingMachine = await RayonUtil.selectOneMachine().first
                    }
                } label: {
                    Label("Select Machine", systemImage: "server.rack")
                        .foregroundColor(.accentColor)
                }
            } header: {
                Label("Machine", systemImage: "server.rack")
            } footer: {
                Text("We will use this machine to create SSH tunnel for you.")
            }

            Section {} footer: { Text(sessionDescription) }
        }
        .onAppear {
            if initializedOnce { return }
            initializedOnce = true
            mainActor(delay: 0.1) {
                if let edit = inEditWith?() {
                    let read = RayonStore.shared.browserSessionGroup[edit]
                    name = read.name
                    remoteHost = read.remoteHost
                    remotePort = read.remotePort
                    usingMachine = read.usingMachine
                }
            }
        }
        .navigationTitle("Edit Browser Session")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    completeSheet()
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
            }
        }
    }

    func completeSheet() {
        var object = generateObject
        if let edit = inEditWith?() {
            object.id = edit
        }
        RayonStore.shared.browserSessionGroup.insert(object)
        presentationMode.wrappedValue.dismiss()
    }
}

struct EditBrowserSessionView_Previews: PreviewProvider {
    static var previews: some View {
        createPreview {
            AnyView(EditBrowserSessionView())
        }
    }
}
