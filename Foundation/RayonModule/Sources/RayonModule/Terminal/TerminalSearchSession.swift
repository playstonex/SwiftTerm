import Combine
import Foundation
import SwiftUI

public struct TerminalSearchResult: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let lineNumber: Int
    public let line: String

    public init(lineNumber: Int, line: String) {
        self.lineNumber = lineNumber
        self.line = line
    }
}

@MainActor
public final class TerminalSearchSession: ObservableObject {
    @Published public var query: String = "" {
        didSet {
            rebuildResults()
        }
    }

    @Published public private(set) var results: [TerminalSearchResult] = []
    @Published public private(set) var selectedIndex: Int = 0

    private let maxResults: Int
    private var transcript: String = ""

    public init(maxResults: Int = 200) {
        self.maxResults = maxResults
    }

    public var selectedResult: TerminalSearchResult? {
        guard results.indices.contains(selectedIndex) else { return nil }
        return results[selectedIndex]
    }

    public var selectionSummary: String {
        guard !results.isEmpty else { return "No matches" }
        return "\(selectedIndex + 1) of \(results.count)"
    }

    public func updateTranscript(_ transcript: String) {
        guard self.transcript != transcript else { return }
        self.transcript = transcript
        rebuildResults()
    }

    public func selectNextMatch() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % results.count
    }

    public func selectPreviousMatch() {
        guard !results.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + results.count) % results.count
    }

    public func selectResult(id: TerminalSearchResult.ID) {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = index
    }

    private func rebuildResults() {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            results = []
            selectedIndex = 0
            return
        }

        var matches: [TerminalSearchResult] = []
        for (index, line) in transcript.components(separatedBy: .newlines).enumerated() {
            guard line.localizedCaseInsensitiveContains(trimmedQuery) else { continue }
            matches.append(
                TerminalSearchResult(
                    lineNumber: index + 1,
                    line: line.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            if matches.count >= maxResults {
                break
            }
        }

        results = matches
        if results.isEmpty {
            selectedIndex = 0
        } else if selectedIndex >= results.count {
            selectedIndex = results.count - 1
        }
    }
}

public struct TerminalSearchPanel: View {
    @ObservedObject private var session: TerminalSearchSession
    @Binding private var isPresented: Bool

    public init(session: TerminalSearchSession, isPresented: Binding<Bool>) {
        self.session = session
        _isPresented = isPresented
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label {
                    TextField("Search transcript", text: $session.query)
                        .textFieldStyle(.roundedBorder)
                } icon: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                }

                Text(session.selectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 64, alignment: .trailing)

                Button {
                    session.selectPreviousMatch()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(session.results.isEmpty)

                Button {
                    session.selectNextMatch()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(session.results.isEmpty)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            if session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Search the captured terminal transcript.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if session.results.isEmpty {
                Text("No transcript lines matched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(session.results.enumerated()), id: \.element.id) { index, result in
                                Button {
                                    session.selectResult(id: result.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Line \(result.lineNumber)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(result.line.isEmpty ? " " : result.line)
                                            .font(.system(.callout, design: .monospaced))
                                            .foregroundStyle(.primary)
                                            .lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(index == session.selectedIndex ? Color.accentColor.opacity(0.18) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(result.id)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                    .onAppear {
                        if let selectedID = session.selectedResult?.id {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                    .onChange(of: session.selectedResult?.id) { _, selectedID in
                        guard let selectedID else { return }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
