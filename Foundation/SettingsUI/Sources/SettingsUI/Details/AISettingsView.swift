//
//  AISettingsView.swift
//  SettingsUI
//
//  Created for GoodTerm
//

#if canImport(AppKit)
import AppKit
#endif
import RayonModule
import SwiftUI

// MARK: - AI Settings View
struct AISettingsView: View {
    @ObservedObject var aiAssistant = AIAssistant.shared
    @Environment(\.dismiss) var dismiss
    @State private var isTesting = false
    @State private var testResult: AIAssistant.TestResult?

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    private var macOSBody: some View {
        VStack(spacing: 0) {
            // Custom Title Bar
            HStack {
                Text("AI Settings")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            #if os(macOS)
            .background(Color(NSColor.windowBackgroundColor))
            #else
            .background(Color(uiColor: .systemBackground))
            #endif

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusSection
                    configurationSection
                    featuresSection
                }
                .padding()
            }
        }
        #if os(macOS)
        .background(Color(NSColor.windowBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
        .frame(minWidth: 550, idealWidth: 600, maxWidth: 700,
               minHeight: 500, idealHeight: 600, maxHeight: 700)
    }

    private var iOSBody: some View {
        Form {
            Section {
                Toggle("Enable AI Assistant", isOn: $aiAssistant.isEnabled)
            } header: {
                Text("Status")
            }

            Section {
                Picker("AI Provider", selection: $aiAssistant.provider) {
                    ForEach(AIAssistant.AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                SecureField("API Key", text: $aiAssistant.apiKey)

                TextField("Custom Base URL (optional)", text: $aiAssistant.customBaseURL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                TextField("Custom Model (optional)", text: $aiAssistant.customModel)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                Button(action: {
                    Task {
                        await testAPIConnection()
                    }
                }) {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Testing...")
                        } else {
                            Image(systemName: "checkmark.circle")
                            Text("Test Connection")
                        }
                    }
                }
                .disabled(isTesting || aiAssistant.apiKey.isEmpty)

                if let result = testResult {
                    HStack(spacing: 12) {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.message)
                                .font(.subheadline)
                                .fontWeight(.medium)

                            if let details = result.details {
                                Text(details)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background((result.success ? Color.green : Color.red).opacity(0.1))
                    .cornerRadius(8)
                }
            } header: {
                Text("Configuration")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Leave custom fields empty to use defaults.")
                        .font(.caption)
                    Text("Your API key is stored locally and never sent to our servers.")
                        .font(.caption)
                    Link("Get OpenAI API Key →", destination: URL(string: "https://platform.openai.com/api-keys")!)
                        .font(.caption)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Command explanation", systemImage: "info.circle")
                    Label("Smart suggestions", systemImage: "lightbulb")
                    Label("Error diagnosis", systemImage: "stethoscope")
                    Label("Natural language to command", systemImage: "wand.and.stars")
                    Label("Command history analysis", systemImage: "chart.bar")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("Features")
            }
        }
        .navigationTitle("AI Settings")
    }

    // MARK: - macOS Sections

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)
                .foregroundColor(.secondary)

            Toggle("Enable AI Assistant", isOn: $aiAssistant.isEnabled)
        }
        .padding()
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(uiColor: .secondarySystemBackground))
        #endif
        .cornerRadius(8)
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)
                .foregroundColor(.secondary)

            Picker("AI Provider", selection: $aiAssistant.provider) {
                ForEach(AIAssistant.AIProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)

            SecureField("API Key", text: $aiAssistant.apiKey)
                .textFieldStyle(.roundedBorder)

            TextField("Custom Base URL (optional)", text: $aiAssistant.customBaseURL)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)

            TextField("Custom Model (optional)", text: $aiAssistant.customModel)
                .disableAutocorrection(true)
                .textFieldStyle(.roundedBorder)

            // Test Connection Button
            Button(action: {
                Task {
                    await testAPIConnection()
                }
            }) {
                HStack {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Testing...")
                    } else {
                        Image(systemName: "checkmark.circle")
                        Text("Test Connection")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTesting || aiAssistant.apiKey.isEmpty)

            // Test Result
            if let result = testResult {
                HStack(spacing: 12) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(result.success ? .green : .red)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.message)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if let details = result.details {
                            Text(details)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background((result.success ? Color.green : Color.red).opacity(0.1))
                .cornerRadius(8)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Leave custom fields empty to use defaults.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Your API key is stored locally and never sent to our servers.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link(destination: URL(string: "https://platform.openai.com/api-keys")!) {
                    Text("Get OpenAI API Key →")
                        .font(.caption)
                }
            }
        }
        .padding()
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(uiColor: .secondarySystemBackground))
        #endif
        .cornerRadius(8)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Features")
                .font(.headline)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label("Command explanation", systemImage: "info.circle")
                Label("Smart suggestions", systemImage: "lightbulb")
                Label("Error diagnosis", systemImage: "stethoscope")
                Label("Natural language to command", systemImage: "wand.and.stars")
                Label("Command history analysis", systemImage: "chart.bar")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        #if os(macOS)
        .background(Color(NSColor.controlBackgroundColor))
        #else
        .background(Color(uiColor: .secondarySystemBackground))
        #endif
        .cornerRadius(8)
    }

    // MARK: - Helper Methods

    private func testAPIConnection() async {
        isTesting = true
        testResult = nil

        let result = await aiAssistant.testConnection()

        DispatchQueue.main.async {
            self.testResult = result
            self.isTesting = false
        }
    }
}
