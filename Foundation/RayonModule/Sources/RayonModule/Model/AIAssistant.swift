//
//  AIAssistant.swift
//  RayonModule
//
//  Created by Claude on 2026/1/29.
//

import Foundation
import Keychain
import Combine

@MainActor
public class AIAssistant: ObservableObject {
    public static let shared = AIAssistant()

    // MARK: - Storage

    private let keychain = Keychain(service: "com.rayon.assistant")
    private let userDefaults = UserDefaults.standard

    // UserDefaults keys for non-sensitive data
    private enum Keys {
        static let provider = "ai.provider"
        static let isEnabled = "ai.enabled"
    }

    // Keychain keys for sensitive data
    private enum KeychainKeys {
        static let apiKey = "ai.apikey"
        static let customBaseURL = "ai.baseurl"
        static let customModel = "ai.model"
    }

    // Prevent saves during initialization
    private var isLoading = false

    // Debounced save cancellables
    private var secureDataCancellable: AnyCancellable?
    private var nonSecureDataCancellable: AnyCancellable?

    private init() {
        loadSettings()
        setupDebouncedSaving()
    }

    // MARK: - Published Properties

    @Published public var apiKey: String = "" {
        didSet { guard !isLoading else { return } }
    }

    @Published public var provider: AIProvider = .openai {
        didSet { guard !isLoading else { return } }
    }

    @Published public var isEnabled: Bool = false {
        didSet { guard !isLoading else { return } }
    }

    // Customizable configuration
    @Published public var customBaseURL: String = "" {
        didSet { guard !isLoading else { return } }
    }

    @Published public var customModel: String = "" {
        didSet { guard !isLoading else { return } }
    }

    // MARK: - Setup

    private func setupDebouncedSaving() {
        // Debounce secure data saves (API key, base URL, model)
        secureDataCancellable = Publishers.Merge3(
            $apiKey.dropFirst().map { _ in () },
            $customBaseURL.dropFirst().map { _ in () },
            $customModel.dropFirst().map { _ in () }
        )
        .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.saveSecureData()
        }

        // Save non-secure data with debounce
        nonSecureDataCancellable = Publishers.Merge(
            $provider.dropFirst().map { _ in () },
            $isEnabled.dropFirst().map { _ in () }
        )
        .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.saveNonSecureData()
        }
    }

    // MARK: - Persistence

    private func loadSettings() {
        isLoading = true
        defer { isLoading = false }

        // Load non-sensitive data from UserDefaults
        if let providerRaw = userDefaults.string(forKey: Keys.provider),
           let savedProvider = AIProvider(rawValue: providerRaw) {
            provider = savedProvider
        }

        isEnabled = userDefaults.bool(forKey: Keys.isEnabled)

        // Load sensitive data from Keychain
        do {
            apiKey = try keychain.get(KeychainKeys.apiKey) ?? ""
            customBaseURL = try keychain.get(KeychainKeys.customBaseURL) ?? ""
            customModel = try keychain.get(KeychainKeys.customModel) ?? ""
        } catch {
            print("Failed to load AI settings from Keychain: \(error)")
        }
    }

    private func saveSecureData() {
        guard !isLoading else { return }

        do {
            try keychain.set(apiKey, key: KeychainKeys.apiKey)
            try keychain.set(customBaseURL, key: KeychainKeys.customBaseURL)
            try keychain.set(customModel, key: KeychainKeys.customModel)
        } catch {
            print("Failed to save AI settings to Keychain: \(error)")
        }
    }

    private func saveNonSecureData() {
        guard !isLoading else { return }

        userDefaults.set(provider.rawValue, forKey: Keys.provider)
        userDefaults.set(isEnabled, forKey: Keys.isEnabled)
    }

    /// Delete all stored AI settings
    public func clearAllData() {
        isLoading = true
        defer { isLoading = false }

        do {
            try keychain.remove(KeychainKeys.apiKey)
            try keychain.remove(KeychainKeys.customBaseURL)
            try keychain.remove(KeychainKeys.customModel)
        } catch {
            print("Failed to clear AI settings from Keychain: \(error)")
        }

        userDefaults.removeObject(forKey: Keys.provider)
        userDefaults.removeObject(forKey: Keys.isEnabled)

        // Reset in-memory values
        apiKey = ""
        customBaseURL = ""
        customModel = ""
        isEnabled = false
        provider = .openai
    }

    // Get effective base URL (custom or default)
    public var effectiveBaseURL: String {
        if !customBaseURL.isEmpty {
            return customBaseURL
        }
        return provider.baseURL
    }

    // Get effective model name (custom or default)
    public var effectiveModel: String {
        if !customModel.isEmpty {
            return customModel
        }
        return provider.defaultModel
    }

    public enum AIProvider: String, CaseIterable, Codable {
        case openai = "OpenAI"
        case anthropic = "Anthropic"
        case local = "Local LLM"

        public var displayName: String {
            switch self {
            case .openai: return "OpenAI (GPT-4)"
            case .anthropic: return "Anthropic (Claude)"
            case .local: return "Local LLM"
            }
        }

        public var baseURL: String {
            switch self {
            case .openai: return "https://api.openai.com/v1"
            case .anthropic: return "https://api.anthropic.com/v1"
            case .local: return "http://localhost:11434/v1"
            }
        }

        public var defaultModel: String {
            switch self {
            case .openai: return "gpt-4"
            case .anthropic: return "claude-3-sonnet-20240229"
            case .local: return "llama2"
            }
        }
    }

    // MARK: - Command Explanation

    public func explainCommand(_ command: String) async throws -> String {
        guard isEnabled, !apiKey.isEmpty else {
            throw AIError.disabled
        }

        let prompt = """
        Explain this Unix/Linux command in simple terms:
        Command: \(command)

        Please provide:
        1. What this command does
        2. Key parameters and their meanings
        3. Common use cases
        4. Any potential risks or warnings

        Keep it concise and beginner-friendly.
        """

        return try await sendChatRequest(prompt)
    }

    // MARK: - Natural Language to Command

    public func naturalLanguageToCommand(_ input: String, context: String? = nil) async throws -> String {
        guard isEnabled, !apiKey.isEmpty else {
            throw AIError.disabled
        }

        var prompt = "Convert this natural language request to a Unix/Linux command:\n\(input)\n\n"

        if let context = context {
            prompt += "Context/Additional info: \(context)\n"
        }

        prompt += """
        Provide ONLY the command, no explanation.
        Make sure the command is practical and follows best practices.

        Example:
        Input: "find files larger than 100MB"
        Output: find . -size +100M

        Command:
        """

        return try await sendChatRequest(prompt)
    }

    // MARK: - Error Diagnosis

    public func diagnoseError(_ errorMessage: String, command: String? = nil) async throws -> String {
        guard isEnabled, !apiKey.isEmpty else {
            throw AIError.disabled
        }

        var prompt = "Help diagnose this Unix/Linux error:\n\n\(errorMessage)\n\n"

        if let command = command {
            prompt += "Command that caused the error: \(command)\n"
        }

        prompt += """
        Please provide:
        1. What the error means
        2. Common causes
        3. Step-by-step solutions (try easiest first)
        4. How to prevent this error

        Be practical and specific.
        """

        return try await sendChatRequest(prompt)
    }

    // MARK: - Command Suggestions

    public func getSuggestions(currentDirectory: String? = nil, recentCommands: [String] = []) async throws -> [String] {
        guard isEnabled, !apiKey.isEmpty else {
            throw AIError.disabled
        }

        var prompt = "Suggest 5 useful Unix/Linux commands that I might want to use."

        if let dir = currentDirectory {
            prompt += "\n\nCurrent directory: \(dir)"
        }

        if !recentCommands.isEmpty {
            prompt += "\n\nRecent commands I've used:\n" + recentCommands.prefix(5).joined(separator: "\n")
        }

        prompt += """

        Provide ONLY the commands, one per line, no explanations.
        Focus on practical, commonly-used commands.
        """

        let response = try await sendChatRequest(prompt)
        return response.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - API Communication

    private func sendChatRequest(_ prompt: String) async throws -> String {
        switch provider {
        case .openai:
            return try await sendOpenAIRequest(prompt)
        case .anthropic:
            return try await sendAnthropicRequest(prompt)
        case .local:
            return try await sendLocalRequest(prompt)
        }
    }

    private func sendOpenAIRequest(_ prompt: String) async throws -> String {
        let url = URL(string: "\(effectiveBaseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let choice = choices.first,
           let message = choice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        throw AIError.invalidResponse
    }

    private func sendAnthropicRequest(_ prompt: String) async throws -> String {
        let url = URL(string: "\(effectiveBaseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "max_tokens": 500,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let contentArray = json["content"] as? [[String: Any]],
           let firstContent = contentArray.first,
           let text = firstContent["text"] as? String {
            return text
        }

        throw AIError.invalidResponse
    }

    private func sendLocalRequest(_ prompt: String) async throws -> String {
        let url = URL(string: "\(effectiveBaseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": effectiveModel,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 500
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let choices = json["choices"] as? [[String: Any]],
           let choice = choices.first,
           let message = choice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }

        throw AIError.invalidResponse
    }

    // MARK: - Connection Test

    public struct TestResult {
        public let success: Bool
        public let message: String
        public let details: String?

        public init(success: Bool, message: String, details: String? = nil) {
            self.success = success
            self.message = message
            self.details = details
        }
    }

    public func testConnection() async -> TestResult {
        guard !apiKey.isEmpty else {
            return TestResult(
                success: false,
                message: "API key is empty",
                details: "Please enter your API key first."
            )
        }

        let testPrompt = "Respond with just: OK"

        do {
            let response = try await sendChatRequest(testPrompt)

            // Check if we got a valid response
            if response.contains("OK") || !response.isEmpty {
                return TestResult(
                    success: true,
                    message: "Connection successful!",
                    details: "Connected to \(provider.displayName) using model: \(effectiveModel)"
                )
            } else {
                return TestResult(
                    success: false,
                    message: "Unexpected response",
                    details: "Received: \(String(response.prefix(100)))"
                )
            }
        } catch let error as AIError {
            return TestResult(
                success: false,
                message: "Connection failed",
                details: error.localizedDescription
            )
        } catch {
            return TestResult(
                success: false,
                message: "Connection failed",
                details: error.localizedDescription
            )
        }
    }

    // MARK: - Skill Support

    /// Send a raw chat request (used by SkillAnalyzer and other components)
    public func sendRawChatRequest(_ prompt: String) async throws -> String {
        try await sendChatRequest(prompt)
    }
}

// MARK: - Errors

public enum AIError: Error {
    case disabled
    case invalidAPIKey
    case invalidResponse
    case networkError(Error)
    case rateLimitExceeded
}

extension AIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .disabled:
            return "AI assistant is disabled. Please enable it in settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your settings."
        case .invalidResponse:
            return "Invalid response from AI service."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimitExceeded:
            return "API rate limit exceeded. Please try again later."
        }
    }
}
