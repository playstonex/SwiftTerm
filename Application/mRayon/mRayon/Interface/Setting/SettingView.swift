//
//  SettingView.swift
//  mRayon
//
//  Created by Lakr Aream on 2022/3/2.
//

import RayonModule
import SwiftUI
import DataSync

struct SettingView: View {
    @StateObject var store = RayonStore.shared

    #if DEBUG
        @State var redirectLog = false
    #endif

    var body: some View {
        List {
            
            Section {
                
                Button {
                    Task {
                        do {
                            let machines = RayonStore.shared.machineGroup.machines
                            
                            try await iCloudStoreSync.share.startSync(items: machines)
                            
                            
                            let identity = RayonStore.shared.identityGroup.identities
                            
                            try await iCloudStoreSync.share.startSync(items: identity)
                            
                            iCloudStoreSync.share.finishSync()
                        }
                        catch let error {
                            print(error)
                        }
                    }
                    
                } label: {
                    Label( "Sync", systemImage:"arrow.counterclockwise.icloud")
                }

            } header: {
                Label("Data sync", systemImage: "arrow.right")
            } footer: {
                Text("last sync at: \(iCloudStoreSync.share.syncDate.ISO8601Format())")
            }

            Section {
                Toggle("Record Recent", isOn: $store.storeRecent)
                Stepper(
                    "Timeout: \(store.timeout)",
                    value: $store.timeout,
                    in: 2 ... 30,
                    step: 1
                ) { _ in }
            } header: {
                Label("Connect", systemImage: "arrow.right")
            }

            Section {
                Toggle("Open at Connect", isOn: $store.openInterfaceAutomatically)
                Toggle("Reduced Effects", isOn: $store.reducedViewEffects)
                Stepper(
                    "Terminal Font Size: \(store.terminalFontSize)",
                    value: $store.terminalFontSize,
                    in: 5 ... 30,
                    step: 1
                ) { _ in }
            } header: {
                Label("Interface", systemImage: "arrow.right")
            }

            Section {
                Button {
                    UIBridge.openFileContainer()
                } label: {
                    Text("Show App Container")
                }
            } header: {
                Label("DOCUMENT", systemImage: "doc.text.magnifyingglass")
            }

            Section {
                #if DEBUG
                    Toggle("Redirect Log", isOn: $redirectLog)
                        .onChange(of: redirectLog) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "wiki.qaq.redirect.diag")
                            debugPrint("redirectLog set to \(newValue), restart to take effect")
                        }
                        .onAppear {
                            redirectLog = UserDefaults.standard.value(forKey: "wiki.qaq.redirect.diag") as? Bool ?? false
                        }
                #endif

                NavigationLink {
                    LogView()
                } label: {
                    Text("Show App Log")
                }
            } header: {
                Label("Diagnostic", systemImage: "doc.text.below.ecg")
            }

            Section {
                NavigationLink {
                    ThanksView()
                } label: {
                    Text("Thanks")
                }

                NavigationLink {
                    LicenseView()
                } label: {
                    Text("Software License")
                }
            } header: {
                Label("License", systemImage: "arrow.right")
            }
        }
        .navigationTitle("Setting")
    }
}

struct SettingView_Previews: PreviewProvider {
    static var previews: some View {
        createPreview {
            AnyView(SettingView())
        }
    }
}
