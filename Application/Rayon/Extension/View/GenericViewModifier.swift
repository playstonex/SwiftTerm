//
//  GenericViewModifier.swift
//  Rayon
//
//  Created by Lakr Aream on 2022/2/9.
//

import SwiftUI

extension View {
    func expended() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func dropShadow() -> some View {
        shadow(color: .black.opacity(DesignTokens.shadowOpacity), radius: DesignTokens.shadowRadius, x: 0, y: DesignTokens.shadowY)
    }

    func requiresFrame(_ width: Double = 500, _ height: Double = 250) -> some View {
        frame(minWidth: width, minHeight: height)
    }

    func requiresSheetFrame(_ width: Double = 450, _ height: Double = 200) -> some View {
        frame(minWidth: width, minHeight: height)
    }

    func makeHoverPointer() -> some View {
        onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    func roundedCorner() -> some View {
        cornerRadius(DesignTokens.cornerRadiusMedium)
    }
}
