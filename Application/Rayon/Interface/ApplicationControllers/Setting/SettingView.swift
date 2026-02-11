//
//  SettingView.swift
//  Rayon (macOS)
//
//  Created by Lakr Aream on 2022/3/10.
//

import RayonModule
import SwiftUI
import DataSync

struct SettingView: View {
    @EnvironmentObject var store: RayonStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                
                Section {
                    Button {
                        Task {
                            do {
                                // try await  RayonStore.shared.uploadMathine()
                                
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
                        Text("Sync")
                    }

                } footer: {
                    Text("last sync at: \(iCloudStoreSync.share.syncDate.ISO8601Format())")
                }
                
                Section {
                    Toggle("Reduced Effect", isOn: $store.reducedViewEffects)
                        .font(.system(.headline, design: .rounded))
                    Text("This option will remove animated blur background and star animation.")
                        .font(.system(.subheadline, design: .rounded))
                    Toggle("Disable Confirmation", isOn: $store.disableConformation)
                        .font(.system(.headline, design: .rounded))
                    Text("This option will remove the confirmation alert, use with caution.")
                        .font(.system(.subheadline, design: .rounded))
                    Toggle("Record Recent", isOn: $store.storeRecent)
                        .font(.system(.headline, design: .rounded))
                    Text("This option will save several most recent used machine.")
                        .font(.system(.subheadline, design: .rounded))
                    Picker("Theme", selection: $store.themePreference) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .font(.system(.headline, design: .rounded))
                    Text("Choose the app appearance.")
                        .font(.system(.subheadline, design: .rounded))
                } header: {
                    Text("Application")
                        .font(.system(.headline, design: .rounded))
                } footer: {
                    Divider()
                }
                Section {
                    Slider(value: Binding<Double>.init(get: {
                        Double(store.timeout)
                    }, set: { newValue in
                        store.timeout = Int(exactly: newValue) ?? 5
                    }), in: 2 ... 30, step: 1) { Group {} }
                    Text("SSH will report invalid connection after \(store.timeout) seconds.")
                        .font(.system(.subheadline, design: .rounded))
                    Slider(value: Binding<Double>.init(get: {
                        Double(store.monitorInterval)
                    }, set: { newValue in
                        store.monitorInterval = Int(exactly: newValue) ?? 5
                    }), in: 5 ... 60, step: 5) { Group {} }
                    Text("Server monitor will update information \(store.monitorInterval) seconds after last attempt.")
                        .font(.system(.subheadline, design: .rounded))
                } header: {
                    Text("Connection")
                        .font(.system(.headline, design: .rounded))
                } footer: {
                    Divider()
                }
                Section {
                    Picker("Terminal Theme", selection: $store.terminalThemeName) {
                        ForEach(TerminalTheme.allThemes, id: \.name) { theme in
                            Text(theme.name).tag(theme.name)
                        }
                    }
                    .font(.system(.headline, design: .rounded))
                    Text("Choose terminal color theme.")
                        .font(.system(.subheadline, design: .rounded))
                    Picker("Terminal Font", selection: $store.terminalFontName) {
                        Text("Menlo").tag("Menlo")
                        Text("Monaco").tag("Monaco")
                        Text("SF Mono").tag("SF Mono")
                        Text("FiraCode Nerd Font Mono").tag("FiraCode Nerd Font Mono")
                        Text("Maple Mono NF CN").tag("Maple Mono NF CN")
                        Text("Cascadia Code NF").tag("Cascadia Code NF")
                        Text("Cascadia Mono NF").tag("Cascadia Mono NF")
                        Text("Hack Nerd Font Mono").tag("Hack Nerd Font Mono")
                        Text("Inconsolata Nerd Font Mono").tag("Inconsolata Nerd Font Mono")
                        Text("JetBrains Mono").tag("JetBrains Mono")
                        Text("Source Code Pro").tag("Source Code Pro")
                    }
                    .font(.system(.headline, design: .rounded))
                    Text("Choose terminal font family.")
                        .font(.system(.subheadline, design: .rounded))

                    Divider()

                    Toggle("Use Tmux Session", isOn: $store.useTmux)
                        .font(.system(.headline, design: .rounded))
                    Text("Enable tmux to preserve session state across reconnections. Sessions and running programs will be restored when reconnecting.")
                        .font(.system(.subheadline, design: .rounded))

                    if store.useTmux {
                        TextField("Tmux Session Name", text: $store.tmuxSessionName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .rounded))
                        Text("Session name to attach or create. Default: \"default\"")
                            .font(.system(.subheadline, design: .rounded))

                        Toggle("Auto-create Session", isOn: $store.tmuxAutoCreate)
                            .font(.system(.headline, design: .rounded))
                        Text("Automatically create a new tmux session if it doesn't exist.")
                            .font(.system(.subheadline, design: .rounded))
                    }
                } header: {
                    Text("Terminal")
                        .font(.system(.headline, design: .rounded))
                } footer: {
                    Divider()
                }
                Section {
                    NavigationLink(destination: AISettingsView()) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.accentColor)
                            Text("AI Assistant")
                                .font(.system(.headline, design: .rounded))
                        }
                    }
                    Text("Configure OpenAI API and AI assistant features for terminal assistance.")
                        .font(.system(.subheadline, design: .rounded))
                } header: {
                    Text("AI")
                        .font(.system(.headline, design: .rounded))
                } footer: {
                    Divider()
                }
                Label("EOF", systemImage: "text.append")
                    .font(.system(.caption2, design: .rounded))
            }
            .padding()
        }
        .navigationTitle("Setting")
    }
}
