//
//  AssistantManager.swift
//  Rayon (macOS)
//
//  Created by Claude on 2026/1/27.
//

import Foundation
import RayonModule
import SwiftUI

class AssistantManager: ObservableObject {
    static let shared = AssistantManager()

    private init() {}

    @Published var isVisible: Bool = false
    @Published var selectedSegment: AssistantSegment = .history

    // Current terminal context for the assistant
    @Published var currentTerminalContext: TerminalManager.Context?

    enum AssistantSegment: String, CaseIterable {
        case history
        case status
        case ai

        var displayName: LocalizedStringKey {
            switch self {
            case .history: return "History"
            case .status: return "Status"
            case .ai: return "AI"
            }
        }

        var icon: String {
            switch self {
            case .history: return "clock.arrow.circlepath"
            case .status: return "chart.line.uptrend.xyaxis"
            case .ai: return "brain"
            }
        }
    }

    func toggle() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isVisible.toggle()
        }
    }

    func show() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isVisible = true
        }
    }

    func hide() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isVisible = false
        }
    }

    func setCurrentContext(_ context: TerminalManager.Context) {
        DispatchQueue.main.async { [self] in
            currentTerminalContext = context
        }
    }

    func clearCurrentContext() {
        DispatchQueue.main.async { [self] in
            currentTerminalContext = nil
            isVisible = false
        }
    }
}
